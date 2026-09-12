defmodule Mensch.Machines.ArpMachine do
  @moduledoc """
  Arpeggiator machine that traverses chord tones using internal traversal
  strategy configuration.

  `note_length_mode` controls duration behavior:

  * `:equal` gives every note the same length.
  * `:align_end` makes all notes end at the chord end.

  Unlike the expressive machines, this one keeps bend and slide at zero and
  derives pressure directly from ADSR level.
  """

  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machine.MachineFrameSequence
  alias Mensch.Machine.NoteFrame
  alias Mensch.Machine.NotePlanItem
  alias Mensch.Machine.VoicingStrategies.Traversal
  alias Mensch.Machines.ArpMachineParams
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @velocity 100

  @type t :: %__MODULE__{params: ArpMachineParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :arp_machine

  def params_module, do: ArpMachineParams

  def default_params, do: ArpMachineParams.default()

  @spec new(ArpMachineParams.t()) :: t()
  def new(%ArpMachineParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      stagger_mbeats: params.stagger_mbeats,
      direction: params.direction,
      octave_min_offset: params.octave_min_offset,
      octave_max_offset: params.octave_max_offset,
      cycle_count: params.cycle_count,
      note_length_mode: params.note_length_mode,
      attack_mbeats: params.attack_mbeats,
      decay_mbeats: params.decay_mbeats,
      release_mbeats: params.release_mbeats,
      attack_curve: params.attack_curve,
      decay_curve: params.decay_curve,
      release_curve: params.release_curve,
      peak_level: params.peak_level,
      sustain_level: params.sustain_level
    }
  end

  def build_frame_sequence(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %ArpMachineParams{} = params = machine_params!(opts)

    frame_mbeats = SampleContext.frame_units(sample_context)

    stagger_mbeats =
      params.stagger_mbeats
      |> then(&SampleContext.mbeats_to_units(sample_context, &1))
      |> snap_mbeats(frame_mbeats)

    chord_duration_mbeats =
      timeline_context
      |> TimelineContext.duration_mbeats()
      |> snap_mbeats(frame_mbeats)

    sample_start_mbeat =
      timeline_context
      |> TimelineContext.start_mbeat(sample_context)
      |> snap_mbeats(frame_mbeats)

    voiced_notes = build_voiced_notes(chord_spec, params)
    note_count = length(voiced_notes)

    effective_stagger_mbeats =
      effective_stagger_mbeats(stagger_mbeats, chord_duration_mbeats, note_count, frame_mbeats)

    note_length_mode = normalize_note_length_mode(params.note_length_mode)

    timed_voiced_notes =
      apply_uniform_timing(
        voiced_notes,
        sample_start_mbeat,
        effective_stagger_mbeats
      )

    planned_notes =
      build_note_plan(timed_voiced_notes)

    planned_notes_with_adsr =
      planned_notes
      |> assign_envelopes(
        effective_stagger_mbeats,
        chord_duration_mbeats,
        note_length_mode,
        sample_context,
        params
      )

    max_note_end_mbeats =
      case planned_notes_with_adsr do
        [] ->
          chord_duration_mbeats

        _ ->
          planned_notes_with_adsr
          |> Enum.map(&(&1.delay_mbeats + &1.adsr.total_mbeats))
          |> Enum.max()
      end

    assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats)

    note_frame_streams =
      Enum.map(planned_notes_with_adsr, fn planned_note ->
        render_note_frame_stream(planned_note, chord_duration_mbeats, frame_mbeats)
      end)

    %MachineFrameSequence{
      frames: stitch_note_frame_streams(note_frame_streams, chord_duration_mbeats, frame_mbeats)
    }
  end

  defp build_note_plan(timed_voiced_notes) do
    Enum.map(timed_voiced_notes, fn voiced_note ->
      note_number = voiced_note.midi_note
      {note_name, octave} = ChordSpec.note_name(note_number)

      NotePlanItem.new(%{
        note_name: note_name,
        octave: octave,
        midi_note: note_number,
        channel: nil,
        velocity: @velocity,
        machine_id: id(),
        chord_instance_id: 0,
        note_instance_id: voiced_note.note_instance_id,
        degree_index: voiced_note.degree_index,
        delay_mbeats: voiced_note.delay_mbeats
      })
    end)
  end

  defp build_voiced_notes(%ChordSpec{} = chord_spec, %ArpMachineParams{} = params) do
    traversal =
      Traversal.new(
        direction: params.direction,
        octave_min_offset: params.octave_min_offset,
        octave_max_offset: params.octave_max_offset,
        cycle_count: params.cycle_count
      )

    Traversal.build_voiced_notes(traversal, chord_spec)
  end

  defp apply_uniform_timing(voiced_notes, sample_start_mbeat, stagger_mbeats) do
    voiced_notes
    |> Enum.with_index()
    |> Enum.map(fn {voiced_note, sequence_index} ->
      delay_mbeats = sample_start_mbeat + sequence_index * stagger_mbeats
      Map.put(voiced_note, :delay_mbeats, delay_mbeats)
    end)
  end

  defp assign_envelopes(
         note_plan,
         stagger_mbeats,
         chord_duration_mbeats,
         note_length_mode,
         sample_context,
         %ArpMachineParams{} = params
       ) do
    note_count = length(note_plan)

    note_plan
    |> Enum.with_index()
    |> Enum.map(fn {%NotePlanItem{} = planned_note, sequence_index} ->
      note_duration_mbeats =
        note_duration_mbeats(
          chord_duration_mbeats,
          stagger_mbeats,
          sequence_index,
          note_count,
          note_length_mode
        )

      adsr = build_adsr(note_duration_mbeats, sample_context, params)

      NotePlanItem.with_adsr(planned_note, adsr)
    end)
  end

  defp build_adsr(
         note_duration_mbeats,
         %SampleContext{} = sample_context,
         %ArpMachineParams{} = params
       ) do
    ADSR.from_mbeats(note_duration_mbeats, sample_context, %{
      attack_mbeats: params.attack_mbeats,
      decay_mbeats: params.decay_mbeats,
      release_mbeats: params.release_mbeats,
      attack_curve: params.attack_curve,
      decay_curve: params.decay_curve,
      release_curve: params.release_curve,
      peak_level: params.peak_level,
      sustain_level: params.sustain_level
    })
  end

  defp render_note_frame_stream(note, duration_mbeats, frame_mbeats) do
    note_end_mbeat = min(note.delay_mbeats + note.adsr.total_mbeats, duration_mbeats)

    for at_mbeat <- note.delay_mbeats..note_end_mbeat//frame_mbeats do
      %{
        at_mbeat: at_mbeat,
        note: note_frame(note, at_mbeat)
      }
    end
  end

  defp stitch_note_frame_streams(note_frame_streams, duration_mbeats, frame_mbeats) do
    notes_by_mbeat =
      note_frame_streams
      |> List.flatten()
      |> Enum.group_by(& &1.at_mbeat, & &1.note)

    dense_frame_mbeats(duration_mbeats, frame_mbeats)
    |> Enum.map(fn at_mbeat ->
      frame_notes =
        notes_by_mbeat
        |> Map.get(at_mbeat, [])
        |> Enum.sort_by(&{&1.note_instance_id, &1.midi_note})

      %{at_mbeat: at_mbeat, notes: frame_notes}
    end)
  end

  defp dense_frame_mbeats(duration_mbeats, frame_mbeats) do
    Enum.to_list(0..duration_mbeats//frame_mbeats)
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

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %ArpMachineParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(ArpMachineParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
  end

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

  defp effective_stagger_mbeats(_stagger_mbeats, _duration_mbeats, note_count, _frame_mbeats)
       when note_count <= 1,
       do: 0

  defp effective_stagger_mbeats(stagger_mbeats, duration_mbeats, note_count, frame_mbeats) do
    max_stagger_for_alignment =
      duration_mbeats
      |> div(note_count - 1)
      |> div(frame_mbeats)
      |> Kernel.*(frame_mbeats)

    min(stagger_mbeats, max_stagger_for_alignment)
  end

  defp equal_note_duration_mbeats(_duration_mbeats, _stagger_mbeats, note_count)
       when note_count == 0,
       do: 0

  defp equal_note_duration_mbeats(duration_mbeats, _stagger_mbeats, note_count)
       when note_count == 1,
       do: duration_mbeats

  defp equal_note_duration_mbeats(duration_mbeats, stagger_mbeats, note_count) do
    duration_mbeats - (note_count - 1) * stagger_mbeats
  end

  defp note_duration_mbeats(_duration_mbeats, _stagger_mbeats, _note_index, note_count, :equal)
       when note_count == 0,
       do: 0

  defp note_duration_mbeats(duration_mbeats, _stagger_mbeats, _note_index, note_count, :equal)
       when note_count == 1,
       do: duration_mbeats

  defp note_duration_mbeats(duration_mbeats, stagger_mbeats, _note_index, note_count, :equal) do
    equal_note_duration_mbeats(duration_mbeats, stagger_mbeats, note_count)
  end

  defp note_duration_mbeats(
         _duration_mbeats,
         _stagger_mbeats,
         _note_index,
         note_count,
         :align_end
       )
       when note_count == 0,
       do: 0

  defp note_duration_mbeats(duration_mbeats, stagger_mbeats, note_index, _note_count, :align_end)
       when is_integer(note_index) and note_index >= 0 do
    max(duration_mbeats - note_index * stagger_mbeats, 0)
  end

  defp normalize_note_length_mode(:align_end), do: :align_end
  defp normalize_note_length_mode(_mode), do: :equal

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats)
       when max_note_end_mbeats == chord_duration_mbeats,
       do: :ok

  defp assert_last_note_ends_at_chord_end!(max_note_end_mbeats, chord_duration_mbeats) do
    raise ArgumentError,
          "arp_machine invariant violated: last note ends at #{max_note_end_mbeats}, expected #{chord_duration_mbeats}"
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.ArpMachine do
  alias Mensch.Machines.ArpMachine

  def id(_machine), do: ArpMachine.id()

  def controls(%ArpMachine{params: params}) do
    %{
      stagger_mbeats: params.stagger_mbeats,
      direction: params.direction,
      octave_min_offset: params.octave_min_offset,
      octave_max_offset: params.octave_max_offset,
      cycle_count: params.cycle_count,
      note_length_mode: params.note_length_mode,
      attack_mbeats: params.attack_mbeats,
      decay_mbeats: params.decay_mbeats,
      release_mbeats: params.release_mbeats,
      attack_curve: params.attack_curve,
      decay_curve: params.decay_curve,
      release_curve: params.release_curve,
      peak_level: params.peak_level,
      sustain_level: params.sustain_level
    }
  end

  def build_frame_sequence(
        %ArpMachine{params: params},
        chord_spec,
        sample_context,
        timeline_context,
        opts
      ) do
    ArpMachine.build_frame_sequence(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
