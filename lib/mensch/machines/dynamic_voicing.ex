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
  alias Mensch.Machine.Pipeline
  alias Mensch.Machine.RenderContextCommon
  alias Mensch.LfoParams
  alias Mensch.Modulation.Lfo
  alias Mensch.Machines.DynamicVoicingParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

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
          lfo_bend: Mensch.LfoParams.t(),
          lfo_pressure: Mensch.LfoParams.t(),
          lfo_slide: Mensch.LfoParams.t(),
          number_of_inversions: 4
        }
  def controls do
    params = default_params()

    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions,
      lfo_pressure: params.lfo_pressure,
      lfo_slide: params.lfo_slide,
      lfo_bend: params.lfo_bend
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %DynamicVoicingParams{} = params = machine_params!(opts) |> hydrate_params()

    Pipeline.build_frame_sequence(
      __MODULE__,
      %__MODULE__{params: params},
      chord_spec,
      sample_context,
      timeline_context,
      opts
    )
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
    |> assign_dynamic_adsr(
      render_context.common.sample_context,
      render_context.common.frame_mbeats,
      render_context.common.absolute_chord_start_mbeat
    )
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

  defp assign_dynamic_adsr(
         note_plan,
         %SampleContext{} = sample_context,
         frame_mbeats,
         absolute_chord_start_mbeat
       ) do
    Enum.map(note_plan, fn plan_note ->
      duration_mbeats = plan_note.duration_mbeats

      attack_mbeats =
        if boundary_start_note?(plan_note, absolute_chord_start_mbeat) do
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

  @impl Pipeline
  @spec render_note_frame_stream(NotePlanItem.t(), RenderContext.t()) :: [map()]
  def render_note_frame_stream(note, %RenderContext{} = render_context) do
    chord_end_mbeat =
      render_context.common.chord_start_mbeat + render_context.common.chord_duration_mbeats

    frame_mbeats = render_context.common.frame_mbeats
    note_end_mbeat = min(note.start_mbeat + note.duration_mbeats, chord_end_mbeat)

    for at_mbeat <- note.start_mbeat..note_end_mbeat//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        note:
          note_frame(
            note,
            at_mbeat,
            render_context
          )
      }
    end
  end

  @impl Pipeline
  @spec stitch_note_frame_streams([[map()]], RenderContext.t()) :: [MachineFrameSequence.frame()]
  def stitch_note_frame_streams(note_frame_streams, %RenderContext{} = render_context) do
    chord_start_mbeat = render_context.common.chord_start_mbeat
    chord_end_mbeat = chord_start_mbeat + render_context.common.chord_duration_mbeats
    frame_mbeats = render_context.common.frame_mbeats

    notes_by_mbeat =
      note_frame_streams
      |> List.flatten()
      |> Enum.group_by(& &1.at_mbeat, & &1.note)

    for at_mbeat <- chord_start_mbeat..chord_end_mbeat//frame_mbeats do
      frame_notes =
        notes_by_mbeat
        |> Map.get(at_mbeat, [])
        |> Enum.sort_by(&{&1.note_instance_id, &1.midi_note})

      %{at_mbeat: at_mbeat, notes: frame_notes}
    end
  end

  @impl Pipeline
  @spec assert_invariants([NotePlanItem.t()], RenderContext.t()) :: :ok
  def assert_invariants(note_plan, %RenderContext{} = render_context) do
    max_note_end_mbeats =
      case note_plan do
        [] ->
          render_context.common.chord_start_mbeat + render_context.common.chord_duration_mbeats

        _ ->
          note_plan |> Enum.map(&(&1.start_mbeat + &1.duration_mbeats)) |> Enum.max()
      end

    assert_last_note_ends_at_chord_end!(
      max_note_end_mbeats,
      render_context.common.chord_start_mbeat + render_context.common.chord_duration_mbeats
    )
  end

  defp boundary_start_note?(plan_note, absolute_chord_start_mbeat) do
    absolute_chord_start_mbeat + plan_note.start_mbeat > 0
  end

  defp note_frame(
         note,
         at_mbeat,
         %RenderContext{} = render_context
       ) do
    local_elapsed_mbeats = at_mbeat - note.start_mbeat
    phase = ADSR.phase_at_mbeat(note.adsr, local_elapsed_mbeats)
    adsr_level = ADSR.level_at_mbeat(note.adsr, local_elapsed_mbeats)

    %SampleContext{} = sample_context = render_context.common.sample_context
    absolute_chord_start_mbeat = render_context.common.absolute_chord_start_mbeat
    %LfoParams{} = pressure_lfo = render_context.params.lfo_pressure
    %LfoParams{} = slide_lfo = render_context.params.lfo_slide
    %LfoParams{} = bend_lfo = render_context.params.lfo_bend

    pressure_lfo_norm =
      Lfo.value_at_mbeat(
        pressure_lfo,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        local_elapsed_mbeats
      )

    baseline_pressure = clamp_7bit(adsr_level * 127)
    pressure = Lfo.apply_to_pressure(baseline_pressure, pressure_lfo_norm, pressure_lfo)

    # Slide modulation is additive over baseline 0; polarity is configured in lfo_slide.
    slide_lfo_norm =
      Lfo.value_at_mbeat(
        slide_lfo,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        local_elapsed_mbeats
      )

    slide = Lfo.apply_additive_to_7bit(0, slide_lfo_norm, slide_lfo)

    bend_lfo_norm =
      Lfo.value_at_mbeat(
        bend_lfo,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        local_elapsed_mbeats
      )

    bend = Lfo.apply_additive_to_bend(0.0, bend_lfo_norm, bend_lfo)

    NoteFrame.from_note_plan_item(note, %{
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.duration_mbeats,
      pressure: pressure,
      bend: bend,
      slide: slide
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

  defp hydrate_params(%DynamicVoicingParams{} = params) do
    defaults = default_params() |> Map.from_struct()
    current = params |> Map.from_struct()

    defaults
    |> Map.merge(current)
    |> Map.update!(:lfo_pressure, &Lfo.normalize!(&1, field_name: "dynamic_voicing lfo_pressure"))
    |> Map.update!(:lfo_slide, &Lfo.normalize!(&1, field_name: "dynamic_voicing lfo_slide"))
    |> Map.update!(:lfo_bend, &Lfo.normalize!(&1, field_name: "dynamic_voicing lfo_bend"))
    |> then(&struct!(DynamicVoicingParams, &1))
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

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_end_mbeat)
       when max_note_end_mbeats == chord_end_mbeat,
       do: :ok

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_end_mbeat) do
    raise ArgumentError,
          "dynamic_voicing invariant violated: last note ends at #{max_note_end_mbeats}, expected #{chord_end_mbeat}"
  end
end

defimpl Mensch.Machine, for: Mensch.Machines.DynamicVoicing do
  alias Mensch.Modulation.Lfo
  alias Mensch.Machines.DynamicVoicing

  def id(_machine), do: DynamicVoicing.id()

  def controls(%DynamicVoicing{params: params}) do
    lfo_pressure =
      Lfo.normalize!(Map.get(params, :lfo_pressure), field_name: "dynamic_voicing lfo_pressure")

    lfo_slide =
      Lfo.normalize!(Map.get(params, :lfo_slide), field_name: "dynamic_voicing lfo_slide")

    lfo_bend =
      Lfo.normalize!(Map.get(params, :lfo_bend), field_name: "dynamic_voicing lfo_bend")

    %{
      direction: params.direction,
      number_of_inversions: params.number_of_inversions,
      lfo_pressure: lfo_pressure,
      lfo_slide: lfo_slide,
      lfo_bend: lfo_bend
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
