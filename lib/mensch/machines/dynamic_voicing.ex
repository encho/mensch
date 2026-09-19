defmodule Mensch.Machines.DynamicVoicing do
  @moduledoc """
  Chord machine that sustains a harmony while changing inversions over time.

  Unlike an arpeggiator, unchanged tones continue to sound across inversion
  boundaries. At each boundary, one tone exits and one new tone enters one
  octave away, following `direction`.
  """

  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machine.NoteFrame
  alias Mensch.Machine.NotePlanItem
  alias Mensch.LfoParams
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @note_on_velocity 100

  @type t :: %__MODULE__{params: DynamicVoicingParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :dynamic_voicing

  def params_module, do: DynamicVoicingParams

  def default_params, do: DynamicVoicingParams.default()

  @spec new(DynamicVoicingParams.t()) :: t()
  def new(%DynamicVoicingParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions,
      lfo_pressure: params.lfo_pressure
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %DynamicVoicingParams{} = params = machine_params!(opts) |> hydrate_params()

    direction = normalize_direction!(params.direction)

    inversion_count =
      params.number_of_inversions
      |> normalize_number_of_inversions!()
      |> validate_inversion_count_for_direction!(direction)

    pressure_lfo = normalize_lfo_pressure!(params.lfo_pressure)

    # Quantization step for this render: how many mbeats each frame advances.
    frame_mbeats = SampleContext.frame_units(sample_context)
    entry_start_mbeat_abs = entry_start_mbeat_abs(opts)

    # Snap total chord duration to the frame grid so slot boundaries land on frame ticks.
    chord_duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    voicing_count =
      effective_voicing_count(
        requested_voicing_count(direction, inversion_count),
        chord_duration_mbeats,
        frame_mbeats
      )

    voicings = build_voicing_sequence(chord_spec, direction, inversion_count, voicing_count)

    slot_boundaries = build_slot_boundaries(chord_duration_mbeats, voicing_count, frame_mbeats)

    planned_notes =
      build_dynamic_note_plan(voicings, slot_boundaries)
      |> assign_dynamic_adsr(sample_context, frame_mbeats, entry_start_mbeat_abs)

    max_note_end_mbeats =
      case planned_notes do
        [] -> chord_duration_mbeats
        _ -> planned_notes |> Enum.map(&(&1.delay_mbeats + &1.adsr.total_mbeats)) |> Enum.max()
      end

    assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats)

    note_frame_streams =
      Enum.map(planned_notes, fn planned_note ->
        render_note_frame_stream(
          planned_note,
          chord_duration_mbeats,
          frame_mbeats,
          sample_context,
          entry_start_mbeat_abs,
          pressure_lfo
        )
      end)

    %MachineFrameSequence{
      frames:
        stitch_note_frame_streams(
          note_frame_streams,
          chord_duration_mbeats,
          frame_mbeats
        )
    }
  end

  defp build_voicing_sequence(
         %ChordSpec{} = chord_spec,
         direction,
         inversion_count,
         voicing_count
       ) do
    first_voicing = ChordSpec.to_midi_notes(chord_spec) |> Enum.sort()

    cycle_step_span = cycle_step_span(direction, inversion_count)

    if voicing_count == 1 do
      [first_voicing]
    else
      1..(voicing_count - 1)
      |> Enum.reduce([first_voicing], fn step, [current | _] = acc ->
        transition_direction = direction_for_step(direction, cycle_step_span, step - 1)
        [next_voicing(current, transition_direction) | acc]
      end)
      |> Enum.reverse()
    end
  end

  defp direction_for_step(:up, _inversion_distance, _step_index), do: :up
  defp direction_for_step(:down, _inversion_distance, _step_index), do: :down

  defp direction_for_step({mode, _cycle_count}, step_span, step_index)
       when mode in [:cycle_up, :cycle_down] and is_integer(step_span) and
              step_span >= 1 and is_integer(step_index) and step_index >= 0 do
    base_direction = if mode == :cycle_up, do: :up, else: :down
    phase = div(step_index, step_span)

    if rem(phase, 2) == 0 do
      base_direction
    else
      opposite_direction(base_direction)
    end
  end

  defp opposite_direction(:up), do: :down
  defp opposite_direction(:down), do: :up

  defp requested_voicing_count(:up, inversion_count), do: inversion_count
  defp requested_voicing_count(:down, inversion_count), do: inversion_count

  defp requested_voicing_count({:cycle_up, cycle_count}, inversion_count),
    do:
      cycle_requested_voicing_count(
        cycle_step_span({:cycle_up, cycle_count}, inversion_count),
        cycle_count
      )

  defp requested_voicing_count({:cycle_down, cycle_count}, inversion_count),
    do:
      cycle_requested_voicing_count(
        cycle_step_span({:cycle_down, cycle_count}, inversion_count),
        cycle_count
      )

  defp cycle_step_span(:up, inversion_count), do: inversion_count
  defp cycle_step_span(:down, inversion_count), do: inversion_count

  defp cycle_step_span({:cycle_up, _cycle_count}, inversion_count) when inversion_count >= 2,
    do: inversion_count - 1

  defp cycle_step_span({:cycle_down, _cycle_count}, inversion_count) when inversion_count >= 2,
    do: inversion_count - 1

  defp cycle_requested_voicing_count(inversion_distance, cycle_count)
       when is_integer(inversion_distance) and inversion_distance >= 1 and is_integer(cycle_count) and
              cycle_count >= 1 do
    inversion_distance * 2 * cycle_count + 1
  end

  defp next_voicing([lowest | rest], :up) do
    Enum.sort(rest ++ [lowest + 12])
  end

  defp next_voicing(notes, :down) do
    highest = List.last(notes)
    front = Enum.drop(notes, -1)
    Enum.sort([highest - 12 | front])
  end

  defp build_slot_boundaries(chord_duration_mbeats, voicing_count, frame_mbeats) do
    total_frames = max(div(chord_duration_mbeats, frame_mbeats), 1)
    base_frames = div(total_frames, voicing_count)
    remainder_frames = rem(total_frames, voicing_count)

    slot_lengths_in_frames =
      for slot_index <- 0..(voicing_count - 1) do
        base_frames + if(slot_index < remainder_frames, do: 1, else: 0)
      end

    _ =
      if Enum.any?(slot_lengths_in_frames, &(&1 <= 0)) do
        raise ArgumentError,
              "dynamic_voicing requires enough duration for #{voicing_count} voicings at frame size #{frame_mbeats}"
      end

    [0 | cumulative_boundaries(0, slot_lengths_in_frames, frame_mbeats)]
  end

  defp cumulative_boundaries(start_mbeat, slot_lengths_in_frames, frame_mbeats) do
    {boundaries, _cursor} =
      Enum.reduce(slot_lengths_in_frames, {[], start_mbeat}, fn slot_frames, {acc, cursor} ->
        next_cursor = cursor + slot_frames * frame_mbeats
        {[next_cursor | acc], next_cursor}
      end)

    Enum.reverse(boundaries)
  end

  defp build_dynamic_note_plan(voicings, slot_boundaries) do
    first_voicing = hd(voicings)
    first_start_mbeat = hd(slot_boundaries)

    initial_active =
      first_voicing
      |> Enum.with_index()
      |> Map.new(fn {midi_note, degree_index} ->
        {midi_note,
         %{
           start_mbeat: first_start_mbeat,
           degree_index: degree_index,
           note_instance_id: degree_index
         }}
      end)

    initial_state = %{
      active: initial_active,
      next_note_instance_id: length(first_voicing),
      planned: []
    }

    stepped_state =
      if length(voicings) <= 1 do
        initial_state
      else
        0..(length(voicings) - 2)
        |> Enum.reduce(initial_state, fn slot_index, state ->
          current_voicing = Enum.at(voicings, slot_index)
          next_voicing_notes = Enum.at(voicings, slot_index + 1)
          transition_mbeat = Enum.at(slot_boundaries, slot_index + 1)

          transition_voicing(state, current_voicing, next_voicing_notes, transition_mbeat)
        end)
      end

    chord_end_mbeat = List.last(slot_boundaries)

    lifecycle_maps =
      stepped_state.active
      |> Enum.reduce(stepped_state.planned, fn {midi_note, active_note}, acc ->
        [plan_note_lifecycle(midi_note, active_note, chord_end_mbeat) | acc]
      end)
      |> Enum.reverse()

    Enum.map(lifecycle_maps, &lifecycle_to_note_plan_item/1)
  end

  defp transition_voicing(state, current_voicing, next_voicing_notes, transition_mbeat) do
    current_set = MapSet.new(current_voicing)
    next_set = MapSet.new(next_voicing_notes)

    to_stop = MapSet.difference(current_set, next_set) |> MapSet.to_list()
    to_start = MapSet.difference(next_set, current_set) |> MapSet.to_list()

    {active_after_stops, planned_after_stops} =
      Enum.reduce(to_stop, {state.active, state.planned}, fn midi_note, {active, planned} ->
        active_note = Map.fetch!(active, midi_note)
        lifecycle = plan_note_lifecycle(midi_note, active_note, transition_mbeat)

        {Map.delete(active, midi_note), [lifecycle | planned]}
      end)

    degree_index_by_note =
      next_voicing_notes
      |> Enum.with_index()
      |> Map.new(fn {midi_note, degree_index} -> {midi_note, degree_index} end)

    {next_active, next_note_instance_id} =
      Enum.reduce(to_start, {active_after_stops, state.next_note_instance_id}, fn midi_note,
                                                                                  {active,
                                                                                   next_id} ->
        new_note = %{
          start_mbeat: transition_mbeat,
          degree_index: Map.get(degree_index_by_note, midi_note, 0),
          note_instance_id: next_id
        }

        {Map.put(active, midi_note, new_note), next_id + 1}
      end)

    %{
      state
      | active: next_active,
        next_note_instance_id: next_note_instance_id,
        planned: planned_after_stops
    }
  end

  defp plan_note_lifecycle(midi_note, active_note, end_mbeat) do
    %{
      midi_note: midi_note,
      start_mbeat: active_note.start_mbeat,
      duration_mbeats: max(end_mbeat - active_note.start_mbeat, 0),
      degree_index: active_note.degree_index,
      note_instance_id: active_note.note_instance_id
    }
  end

  defp lifecycle_to_note_plan_item(plan) do
    {note_name, octave} = ChordSpec.note_name(plan.midi_note)

    note_plan_item =
      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: plan.midi_note,
        channel: nil,
        note_on_velocity: @note_on_velocity,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: plan.note_instance_id,
        degree_index: plan.degree_index,
        delay_mbeats: plan.start_mbeat
      })

    {note_plan_item, plan.duration_mbeats}
  end

  defp assign_dynamic_adsr(
         note_plan,
         %SampleContext{} = sample_context,
         frame_mbeats,
         entry_start_mbeat_abs
       ) do
    Enum.map(note_plan, fn {plan_note, duration_mbeats} ->
      attack_mbeats =
        if boundary_start_note?(plan_note, entry_start_mbeat_abs) do
          frame_mbeats
        else
          frame_mbeats * 2
        end

      adsr = dynamic_adsr(duration_mbeats, sample_context, frame_mbeats, attack_mbeats)

      NotePlanItem.with_adsr(plan_note, adsr)
    end)
  end

  defp dynamic_adsr(
         duration_mbeats,
         %SampleContext{} = sample_context,
         frame_mbeats,
         attack_mbeats
       ) do
    attack_mbeats = min(attack_mbeats, duration_mbeats)
    remaining_after_attack = max(duration_mbeats - attack_mbeats, 0)
    decay_mbeats = min(frame_mbeats * 2, remaining_after_attack)

    ADSR.from_mbeats(duration_mbeats, sample_context, %{
      attack_mbeats: attack_mbeats,
      decay_mbeats: decay_mbeats,
      release_mbeats: 0,
      attack_curve: :linear,
      decay_curve: :linear,
      release_curve: :linear,
      peak_level: 1.0,
      sustain_level: 0.78
    })
  end

  defp render_note_frame_stream(
         note,
         absolute_end_mbeat,
         frame_mbeats,
         %SampleContext{} = sample_context,
         entry_start_mbeat_abs,
         %LfoParams{} = pressure_lfo
       ) do
    note_end_mbeat = min(note.delay_mbeats + note.adsr.total_mbeats, absolute_end_mbeat)

    for at_mbeat <- note.delay_mbeats..note_end_mbeat//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        note:
          note_frame(
            note,
            at_mbeat,
            sample_context,
            entry_start_mbeat_abs,
            pressure_lfo
          )
      }
    end
  end

  defp stitch_note_frame_streams(note_frame_streams, absolute_end_mbeat, frame_mbeats) do
    notes_by_mbeat =
      note_frame_streams
      |> List.flatten()
      |> Enum.group_by(& &1.at_mbeat, & &1.note)

    for at_mbeat <- 0..absolute_end_mbeat//frame_mbeats do
      frame_notes =
        notes_by_mbeat
        |> Map.get(at_mbeat, [])
        |> Enum.sort_by(&{&1.note_instance_id, &1.midi_note})

      %{at_mbeat: at_mbeat, notes: frame_notes}
    end
  end

  defp boundary_start_note?(plan_note, entry_start_mbeat_abs) do
    entry_start_mbeat_abs + plan_note.delay_mbeats > 0
  end

  defp entry_start_mbeat_abs(opts) do
    case Keyword.get(opts, :entry_start_mbeat_abs, 0) do
      value when is_integer(value) and value >= 0 -> value
      other -> raise ArgumentError, "invalid :entry_start_mbeat_abs: #{inspect(other)}"
    end
  end

  defp note_frame(
         note,
         at_mbeat,
         %SampleContext{} = sample_context,
         entry_start_mbeat_abs,
         %LfoParams{} = pressure_lfo
       ) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    phase = ADSR.phase_at_mbeat(note.adsr, local_elapsed_mbeats)
    adsr_level = ADSR.level_at_mbeat(note.adsr, local_elapsed_mbeats)

    pressure_lfo_norm =
      pressure_lfo_value(
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        pressure_lfo.curve,
        pressure_lfo.cycles_per_bar,
        pressure_lfo.shift_mbeats,
        pressure_lfo.time_base
      )

    pressure =
      pressure_with_lfo(
        adsr_level,
        pressure_lfo_norm,
        pressure_lfo.scale,
        pressure_lfo.mode
      )

    NoteFrame.from_note_plan_item(note, %{
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.adsr.total_mbeats,
      pressure: pressure,
      bend: 0.0,
      slide: 0
    })
  end

  defp pressure_with_lfo(adsr_level, lfo_norm, scale, :additive) do
    normalized = adsr_level + lfo_norm * adsr_level * scale
    clamp_7bit(normalized * 127)
  end

  defp pressure_with_lfo(adsr_level, lfo_norm, scale, :multiplicative) do
    normalized = adsr_level * (1 + lfo_norm * adsr_level * scale)
    clamp_7bit(normalized * 127)
  end

  defp pressure_lfo_value(
         at_mbeat,
         %SampleContext{} = sample_context,
         entry_start_mbeat_abs,
         curve,
         cycles_per_bar,
         shift_mbeats,
         time_base
       ) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)

    timeline_mbeat =
      case time_base do
        :absolute -> entry_start_mbeat_abs + at_mbeat
        :entry_local -> at_mbeat
      end

    shifted_mbeat = timeline_mbeat + shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_waveform_value(curve, cycle_phase)
  end

  defp lfo_waveform_value(:sine, cycle_phase), do: :math.sin(2 * :math.pi() * cycle_phase)
  defp lfo_waveform_value(:triangle, cycle_phase), do: 1.0 - 4.0 * abs(cycle_phase - 0.5)
  defp lfo_waveform_value(:saw_up, cycle_phase), do: cycle_phase
  defp lfo_waveform_value(:saw_down, cycle_phase), do: -cycle_phase
  defp lfo_waveform_value(:square, cycle_phase), do: if(cycle_phase < 0.5, do: 1.0, else: -1.0)

  defp effective_voicing_count(requested_voicing_count, chord_duration_mbeats, frame_mbeats) do
    total_frames = max(div(chord_duration_mbeats, frame_mbeats), 1)

    if requested_voicing_count > total_frames do
      raise ArgumentError,
            "dynamic_voicing requested #{requested_voicing_count} voicings but only #{total_frames} frame slots are available for this chord duration/frame size"
    end

    requested_voicing_count
  end

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %DynamicVoicingParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(DynamicVoicingParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
  end

  # Some in-memory/persisted samples may carry legacy structs that predate
  # newly added fields. Merge onto defaults so missing keys are safely hydrated.
  defp hydrate_params(%DynamicVoicingParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    lfo_pressure =
      current
      |> Map.get(:lfo_pressure)
      |> hydrate_lfo_pressure(current)

    legacy_keys = [
      :pressure_lfo_curve,
      :pressure_lfo_scale,
      :pressure_lfo_cycles_per_bar,
      :pressure_lfo_shift_mbeats,
      :pressure_lfo_time_base,
      :pressure_lfo_mode
    ]

    defaults
    |> Map.merge(Map.drop(current, legacy_keys))
    |> Map.put(:lfo_pressure, lfo_pressure)
    |> then(&struct!(DynamicVoicingParams, &1))
  end

  defp hydrate_lfo_pressure(%LfoParams{} = lfo_pressure, current) do
    lfo_pressure
    |> Map.from_struct()
    |> apply_legacy_lfo_overrides(current)
    |> then(&struct!(LfoParams, &1))
  end

  defp hydrate_lfo_pressure(lfo_pressure, current) when is_map(lfo_pressure) do
    LfoParams.default()
    |> Map.from_struct()
    |> Map.merge(Map.drop(lfo_pressure, [:__struct__]))
    |> apply_legacy_lfo_overrides(current)
    |> then(&struct!(LfoParams, &1))
  end

  defp hydrate_lfo_pressure(_other, current) do
    LfoParams.default()
    |> Map.from_struct()
    |> apply_legacy_lfo_overrides(current)
    |> then(&struct!(LfoParams, &1))
  end

  defp apply_legacy_lfo_overrides(lfo_map, current) do
    lfo_map
    |> maybe_put_legacy(current, :curve, :pressure_lfo_curve)
    |> maybe_put_legacy(current, :scale, :pressure_lfo_scale)
    |> maybe_put_legacy(current, :cycles_per_bar, :pressure_lfo_cycles_per_bar)
    |> maybe_put_legacy(current, :shift_mbeats, :pressure_lfo_shift_mbeats)
    |> maybe_put_legacy(current, :time_base, :pressure_lfo_time_base)
    |> maybe_put_legacy(current, :mode, :pressure_lfo_mode)
  end

  defp maybe_put_legacy(map, current, target_key, legacy_key) do
    if Map.has_key?(current, legacy_key) do
      Map.put(map, target_key, Map.get(current, legacy_key))
    else
      map
    end
  end

  defp normalize_lfo_pressure!(%LfoParams{} = lfo_pressure) do
    %LfoParams{
      curve: normalize_pressure_lfo_curve!(lfo_pressure.curve),
      scale: normalize_pressure_lfo_scale!(lfo_pressure.scale),
      cycles_per_bar: normalize_pressure_lfo_cycles_per_bar!(lfo_pressure.cycles_per_bar),
      shift_mbeats: normalize_pressure_lfo_shift_mbeats!(lfo_pressure.shift_mbeats),
      time_base: normalize_pressure_lfo_time_base!(lfo_pressure.time_base),
      mode: normalize_pressure_lfo_mode!(lfo_pressure.mode)
    }
  end

  defp normalize_lfo_pressure!(lfo_pressure) when is_map(lfo_pressure) do
    LfoParams.default()
    |> Map.from_struct()
    |> Map.merge(Map.drop(lfo_pressure, [:__struct__]))
    |> then(&struct!(LfoParams, &1))
    |> normalize_lfo_pressure!()
  end

  defp normalize_lfo_pressure!(other) do
    raise ArgumentError,
          "dynamic_voicing lfo_pressure must be #{inspect(LfoParams)}, got: #{inspect(other)}"
  end

  defp normalize_direction!(:up), do: :up
  defp normalize_direction!(:down), do: :down

  defp normalize_direction!({:cycle_up, cycle_count})
       when is_integer(cycle_count) and cycle_count >= 1,
       do: {:cycle_up, cycle_count}

  defp normalize_direction!({:cycle_down, cycle_count})
       when is_integer(cycle_count) and cycle_count >= 1,
       do: {:cycle_down, cycle_count}

  defp normalize_direction!(other) do
    raise ArgumentError,
          "dynamic_voicing direction must be :up, :down, {:cycle_up, n}, or {:cycle_down, n} with n >= 1, got: #{inspect(other)}"
  end

  defp normalize_number_of_inversions!(value) when is_integer(value) and value >= 1, do: value

  defp normalize_number_of_inversions!(other) do
    raise ArgumentError,
          "dynamic_voicing number_of_inversions must be >= 1, got: #{inspect(other)}"
  end

  defp validate_inversion_count_for_direction!(inversion_count, {:cycle_up, _cycle_count})
       when inversion_count >= 2,
       do: inversion_count

  defp validate_inversion_count_for_direction!(inversion_count, {:cycle_down, _cycle_count})
       when inversion_count >= 2,
       do: inversion_count

  defp validate_inversion_count_for_direction!(inversion_count, {:cycle_up, _cycle_count}) do
    raise ArgumentError,
          "dynamic_voicing number_of_inversions must be >= 2 for cycle directions (it counts total voicing states per leg), got: #{inspect(inversion_count)}"
  end

  defp validate_inversion_count_for_direction!(inversion_count, {:cycle_down, _cycle_count}) do
    raise ArgumentError,
          "dynamic_voicing number_of_inversions must be >= 2 for cycle directions (it counts total voicing states per leg), got: #{inspect(inversion_count)}"
  end

  defp validate_inversion_count_for_direction!(inversion_count, _direction), do: inversion_count

  defp normalize_pressure_lfo_curve!(curve)
       when curve in [:sine, :triangle, :saw_up, :saw_down, :square],
       do: curve

  defp normalize_pressure_lfo_curve!(:sin), do: :sine
  defp normalize_pressure_lfo_curve!(:saw), do: :saw_up

  defp normalize_pressure_lfo_curve!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_curve must be one of :sine, :triangle, :saw_up, :saw_down, :square, got: #{inspect(other)}"
  end

  defp normalize_pressure_lfo_scale!(value) when is_integer(value), do: value * 1.0
  defp normalize_pressure_lfo_scale!(value) when is_float(value), do: value

  defp normalize_pressure_lfo_scale!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_scale must be a number, got: #{inspect(other)}"
  end

  defp normalize_pressure_lfo_cycles_per_bar!(value) when is_integer(value) and value > 0,
    do: value * 1.0

  defp normalize_pressure_lfo_cycles_per_bar!(value) when is_float(value) and value > 0,
    do: value

  defp normalize_pressure_lfo_cycles_per_bar!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_cycles_per_bar must be > 0, got: #{inspect(other)}"
  end

  defp normalize_pressure_lfo_shift_mbeats!(value) when is_integer(value), do: value * 1.0
  defp normalize_pressure_lfo_shift_mbeats!(value) when is_float(value), do: value

  defp normalize_pressure_lfo_shift_mbeats!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_shift_mbeats must be a number, got: #{inspect(other)}"
  end

  defp normalize_pressure_lfo_time_base!(time_base) when time_base in [:absolute, :entry_local],
    do: time_base

  defp normalize_pressure_lfo_time_base!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_time_base must be :absolute or :entry_local, got: #{inspect(other)}"
  end

  defp normalize_pressure_lfo_mode!(mode) when mode in [:additive, :multiplicative], do: mode

  defp normalize_pressure_lfo_mode!(other) do
    raise ArgumentError,
          "dynamic_voicing pressure_lfo_mode must be :additive or :multiplicative, got: #{inspect(other)}"
  end

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_end_mbeat)
       when max_note_end_mbeats == chord_end_mbeat,
       do: :ok

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_end_mbeat) do
    raise ArgumentError,
          "dynamic_voicing invariant violated: last note ends at #{max_note_end_mbeats}, expected #{chord_end_mbeat}"
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.DynamicVoicing do
  alias Mensch.Machines.DynamicVoicing
  alias Mensch.LfoParams

  def id(_machine), do: DynamicVoicing.id()

  def controls(%DynamicVoicing{params: params}) do
    lfo_pressure =
      case Map.get(params, :lfo_pressure) do
        %LfoParams{} = lfo ->
          lfo

        lfo when is_map(lfo) ->
          LfoParams.default()
          |> Map.from_struct()
          |> Map.merge(Map.drop(lfo, [:__struct__]))
          |> then(&struct!(LfoParams, &1))

        _ ->
          %LfoParams{
            curve: Map.get(params, :pressure_lfo_curve, :sine),
            scale: Map.get(params, :pressure_lfo_scale, 0.0),
            cycles_per_bar: Map.get(params, :pressure_lfo_cycles_per_bar, 1.0),
            shift_mbeats: Map.get(params, :pressure_lfo_shift_mbeats, 0.0),
            time_base: Map.get(params, :pressure_lfo_time_base, :absolute),
            mode: Map.get(params, :pressure_lfo_mode, :additive)
          }
      end

    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions,
      lfo_pressure: lfo_pressure
    }
  end

  def build_frame_sequence(
        %DynamicVoicing{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    DynamicVoicing.build_frame_sequence(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
