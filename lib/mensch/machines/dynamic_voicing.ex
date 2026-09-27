defmodule Mensch.Machines.DynamicVoicing do
  @moduledoc """
  Chord machine that sustains a harmony while changing inversions over time.

  Unlike an arpeggiator, unchanged tones continue to sound across inversion
  boundaries. At each boundary, one tone exits and one new tone enters one
  octave away, following `direction`.

  Modulation model:

  - pressure baseline is generated per-note from a dynamic `LfoEnvelope`
  - pressure/slide/bend modulation lanes are computed internally in
    `with_note_modulators/2`
  """

  alias Mensch.ChordSpec
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.Modulation
  alias Mensch.Modulation.Lfo
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoEnvelope
  alias Mensch.Modulation.LfoGroup

  defmodule RenderContext do
    @moduledoc false

    alias Mensch.Machine.RenderContextCommon
    alias Mensch.Machines.DynamicVoicingParams

    @enforce_keys [:params, :common]

    defstruct [:params, :common]

    @type t :: %__MODULE__{
            params: DynamicVoicingParams.t(),
            common: RenderContextCommon.t()
          }
  end

  @note_on_velocity 100

  @type t :: %__MODULE__{params: DynamicVoicingParams.t()}

  @behaviour Pipeline

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :dynamic_voicing

  def params_module, do: DynamicVoicingParams

  def default_params, do: DynamicVoicingParams.default()

  @spec new(DynamicVoicingParams.t()) :: t()
  def new(%DynamicVoicingParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  @spec controls() :: %{
          direction: :up,
          number_of_inversions: 4
        }
  def controls do
    params = default_params()

    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions
    }
  end

  @impl Pipeline
  @spec build_render_context(t(), RenderContextCommon.common_fields()) ::
          RenderContext.t()
  def build_render_context(
        %__MODULE__{params: params},
        %RenderContextCommon{} = common
      ) do
    struct!(RenderContext, %{params: params, common: common})
  end

  @impl Pipeline
  @spec build_note_plan(t(), ChordSpec.t(), RenderContext.t()) :: [NotePlanItem.t()]
  def build_note_plan(%__MODULE__{}, %ChordSpec{} = chord_spec, %RenderContext{} = render_context) do
    params = render_context.params
    direction = normalize_direction!(params.direction)

    inversion_count =
      params.number_of_inversions
      |> normalize_number_of_inversions!()
      |> validate_inversion_count_for_direction!(direction)

    voicing_count =
      effective_voicing_count(
        requested_voicing_count(direction, inversion_count),
        render_context.common.chord_duration_mbeats,
        render_context.common.frame_mbeats
      )

    voicings = build_voicing_sequence(chord_spec, direction, inversion_count, voicing_count)

    slot_boundaries =
      build_slot_boundaries(
        render_context.common.chord_start_mbeat,
        render_context.common.chord_duration_mbeats,
        voicing_count,
        render_context.common.frame_mbeats
      )

    build_dynamic_note_plan(voicings, slot_boundaries)
  end

  @impl Pipeline
  @spec with_note_modulators(NotePlanItem.t(), RenderContext.t()) :: NotePlanItem.t()
  def with_note_modulators(%NotePlanItem{} = note, %RenderContext{} = render_context) do
    pressure_lane = pressure_lane(note, render_context)
    slide_lane = slide_lane(note, render_context)
    bend_lane = bend_lane(note, render_context)
    sample_context = render_context.common.sample_context
    absolute_chord_start_mbeat = render_context.common.absolute_chord_start_mbeat
    frame_mbeats = render_context.common.frame_mbeats

    envelope_profile = %{
      attack_mbeats: 120.0,
      decay_mbeats: 280.0,
      release_mbeats: 120.0,
      sustain_level: 0.68
    }

    baseline_pressure_lfo =
      dynamic_pressure_envelope(
        note,
        frame_mbeats,
        absolute_chord_start_mbeat,
        envelope_profile
      )

    NotePlanItem.with_modulators(note, %{
      pressure_modulator: fn at_mbeat, local_elapsed_mbeats ->
        baseline_pressure =
          baseline_pressure_lfo
          |> Lfo.evaluate(
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )
          |> clamp_7bit()

        pressure_modulation =
          evaluate_lane_modulation(
            pressure_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        Modulation.apply_to_pressure(baseline_pressure, pressure_modulation, pressure_lane.mode)
      end,
      slide_modulator: fn at_mbeat, local_elapsed_mbeats ->
        slide_modulation =
          evaluate_lane_modulation(
            slide_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        apply_to_7bit(0, slide_modulation, slide_lane.mode)
      end,
      bend_modulator: fn at_mbeat, local_elapsed_mbeats ->
        bend_modulation =
          evaluate_lane_modulation(
            bend_lane,
            at_mbeat,
            sample_context,
            absolute_chord_start_mbeat,
            local_elapsed_mbeats
          )

        apply_to_bend(0.0, bend_modulation, bend_lane.mode)
      end
    })
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

  defp build_slot_boundaries(
         chord_start_mbeat,
         chord_duration_mbeats,
         voicing_count,
         frame_mbeats
       ) do
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

    [
      chord_start_mbeat
      | cumulative_boundaries(chord_start_mbeat, slot_lengths_in_frames, frame_mbeats)
    ]
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
           note_instance_id: degree_index,
           harmonic_tags: harmonic_tags_for_degree(degree_index),
           role_tags: [],
           machine_note_tags: []
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
        degree_index = Map.get(degree_index_by_note, midi_note, 0)

        new_note = %{
          start_mbeat: transition_mbeat,
          degree_index: degree_index,
          note_instance_id: next_id,
          harmonic_tags: harmonic_tags_for_degree(degree_index),
          role_tags: [],
          machine_note_tags: []
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
      note_instance_id: active_note.note_instance_id,
      harmonic_tags: active_note.harmonic_tags,
      role_tags: active_note.role_tags,
      machine_note_tags: active_note.machine_note_tags
    }
  end

  defp lifecycle_to_note_plan_item(plan) do
    {note_name, octave} = ChordSpec.note_name(plan.midi_note)

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
      harmonic_tags: plan.harmonic_tags,
      role_tags: plan.role_tags,
      machine_note_tags: plan.machine_note_tags,
      start_mbeat: plan.start_mbeat,
      duration_mbeats: plan.duration_mbeats
    })
  end

  defp effective_voicing_count(requested_voicing_count, chord_duration_mbeats, frame_mbeats) do
    total_frames = max(div(chord_duration_mbeats, frame_mbeats), 1)

    if requested_voicing_count > total_frames do
      raise ArgumentError,
            "dynamic_voicing requested #{requested_voicing_count} voicings but only #{total_frames} frame slots are available for this chord duration/frame size"
    end

    requested_voicing_count
  end

  @doc false
  @spec normalize_params(DynamicVoicingParams.t()) :: DynamicVoicingParams.t()
  def normalize_params(%DynamicVoicingParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> then(&struct!(DynamicVoicingParams, &1))
  end

  defp evaluate_lane_modulation(
         %{lfo: lfo},
         at_mbeat,
         sample_context,
         absolute_chord_start_mbeat,
         local_elapsed_mbeats
       ) do
    Lfo.evaluate(
      lfo,
      at_mbeat,
      sample_context,
      absolute_chord_start_mbeat,
      local_elapsed_mbeats
    )
  end

  defp dynamic_pressure_envelope(
         note,
         _frame_mbeats,
         _absolute_chord_start_mbeat,
         envelope_profile
       ) do
    note_duration = note.duration_mbeats * 1.0
    attack_mbeats = envelope_profile.attack_mbeats
    decay_mbeats = envelope_profile.decay_mbeats
    release_mbeats = envelope_profile.release_mbeats
    total_requested = attack_mbeats + decay_mbeats + release_mbeats

    if total_requested > note_duration do
      raise ArgumentError,
            "dynamic_voicing pressure envelope exceeds note duration: attack(#{attack_mbeats}) + decay(#{decay_mbeats}) + release(#{release_mbeats}) = #{total_requested} > note duration #{note_duration} for note_instance_id #{note.note_instance_id}"
    end

    hold_mbeats = note_duration - total_requested

    %LfoEnvelope{
      start_value: 0.0,
      peak_value: 127.0,
      sustain_value: envelope_profile.sustain_level * 127.0,
      end_value: 0.0,
      attack_mbeats: attack_mbeats,
      decay_mbeats: decay_mbeats,
      hold_mbeats: hold_mbeats,
      release_mbeats: release_mbeats,
      interpolation_function: :linear,
      shift_mbeats: 0.0,
      anchor: :note
    }
  end

  defp apply_to_7bit(baseline_7bit, modulation_value, :add) do
    normalized = baseline_7bit / 127 + modulation_value
    clamp_7bit(normalized * 127)
  end

  defp apply_to_7bit(baseline_7bit, modulation_value, :multiply) do
    normalized = baseline_7bit / 127 * (1 + modulation_value)
    clamp_7bit(normalized * 127)
  end

  defp apply_to_bend(baseline_bend, modulation_value, :add) do
    clamp_bend(baseline_bend + modulation_value)
  end

  defp apply_to_bend(baseline_bend, modulation_value, :multiply) do
    clamp_bend(baseline_bend * (1 + modulation_value))
  end

  defp pressure_lane(%NotePlanItem{}, %RenderContext{}) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{
          initial: %LfoCurve{
            curve: :sine,
            min_value: -0.25,
            max_value: 0.25,
            cycles_per_bar: 10.0,
            shift_mbeats: 0.0,
            anchor: :sample
          },
          operations: []
        },
        mode: :add
      },
      "dynamic_voicing internal pressure lane"
    )
  end

  defp slide_lane(%NotePlanItem{}, %RenderContext{}) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{initial: %LfoCurve{min_value: 0.0, max_value: 0.0}, operations: []},
        mode: :add
      },
      "dynamic_voicing internal slide lane"
    )
  end

  defp bend_lane(%NotePlanItem{}, %RenderContext{}) do
    Modulation.normalize_lfo_pressure!(
      %{
        lfo: %LfoGroup{initial: %LfoCurve{min_value: 0.0, max_value: 0.0}, operations: []},
        mode: :add
      },
      "dynamic_voicing internal bend lane"
    )
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

  defp harmonic_tags_for_degree(0), do: [:root]
  defp harmonic_tags_for_degree(1), do: [:third]
  defp harmonic_tags_for_degree(2), do: [:fifth]
  defp harmonic_tags_for_degree(3), do: [:seventh]
  defp harmonic_tags_for_degree(_), do: [:tension]

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
  defp clamp_bend(value), do: value |> max(-1.0) |> min(1.0)
end

defimpl Mensch.Machine, for: Mensch.Machines.DynamicVoicing do
  alias Mensch.Machines.DynamicVoicing

  def id(_machine), do: DynamicVoicing.id()

  def controls(%DynamicVoicing{params: params}) do
    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions
    }
  end

  def build_frame_sequence(
        %DynamicVoicing{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    normalized_params = DynamicVoicing.normalize_params(params)

    Mensch.Machine.Pipeline.build_frame_sequence(
      DynamicVoicing,
      %DynamicVoicing{params: normalized_params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
  end
end
