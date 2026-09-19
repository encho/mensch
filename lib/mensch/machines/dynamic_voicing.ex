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
      number_of_inversions: params.number_of_inversions
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %DynamicVoicingParams{} = params = machine_params!(opts)

    direction = normalize_direction!(params.direction)
    requested_voicing_count = normalize_number_of_inversions!(params.number_of_inversions)

    # Quantization step for this render: how many mbeats each frame advances.
    frame_mbeats = SampleContext.frame_units(sample_context)
    entry_start_mbeat_abs = entry_start_mbeat_abs(opts)

    # Snap total chord duration to the frame grid so slot boundaries land on frame ticks.
    chord_duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    voicing_count =
      effective_voicing_count(requested_voicing_count, chord_duration_mbeats, frame_mbeats)

    voicings = build_voicing_sequence(chord_spec, direction, voicing_count)
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
        render_note_frame_stream(planned_note, chord_duration_mbeats, frame_mbeats)
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

  defp build_voicing_sequence(%ChordSpec{} = chord_spec, direction, voicing_count) do
    first_voicing = ChordSpec.to_midi_notes(chord_spec) |> Enum.sort()

    if voicing_count == 1 do
      [first_voicing]
    else
      1..(voicing_count - 1)
      |> Enum.reduce([first_voicing], fn _step, [current | _] = acc ->
        [next_voicing(current, direction) | acc]
      end)
      |> Enum.reverse()
    end
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

  defp render_note_frame_stream(note, absolute_end_mbeat, frame_mbeats) do
    note_end_mbeat = min(note.delay_mbeats + note.adsr.total_mbeats, absolute_end_mbeat)

    for at_mbeat <- note.delay_mbeats..note_end_mbeat//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        note: note_frame(note, at_mbeat)
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

  defp note_frame(note, at_mbeat) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    phase = ADSR.phase_at_mbeat(note.adsr, local_elapsed_mbeats)

    NoteFrame.from_note_plan_item(note, %{
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.adsr.total_mbeats,
      pressure:
        ADSR.level_at_mbeat(note.adsr, local_elapsed_mbeats) |> then(&(&1 * 127)) |> clamp_7bit(),
      bend: 0.0,
      slide: 0
    })
  end

  defp effective_voicing_count(requested_voicing_count, chord_duration_mbeats, frame_mbeats) do
    total_frames = max(div(chord_duration_mbeats, frame_mbeats), 1)
    min(requested_voicing_count, total_frames)
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

  defp normalize_direction!(:up), do: :up
  defp normalize_direction!(:down), do: :down

  defp normalize_direction!(other) do
    raise ArgumentError,
          "dynamic_voicing direction must be :up or :down, got: #{inspect(other)}"
  end

  defp normalize_number_of_inversions!(value) when is_integer(value) and value >= 1, do: value

  defp normalize_number_of_inversions!(other) do
    raise ArgumentError,
          "dynamic_voicing number_of_inversions must be >= 1, got: #{inspect(other)}"
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
    DynamicVoicing.build_frame_sequence(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
