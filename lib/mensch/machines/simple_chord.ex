defmodule Mensch.Machines.SimpleChord do
  @moduledoc """
  Simple machine that plays full chords with a configurable note stagger and
  internally computed per-note durations.

  `note_length_mode` controls duration behavior:

  * `:equal` gives every note the same length.
  * `:align_end` makes all notes end at the chord end.

  Unlike the expressive machines, this one keeps bend and slide at zero and
  derives pressure directly from ADSR level.
  """

  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machines.SimpleChordParams
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @velocity 100

  @type t :: %__MODULE__{params: SimpleChordParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :simple_chord

  def params_module, do: SimpleChordParams

  def default_params, do: SimpleChordParams.default()

  @spec new(SimpleChordParams.t()) :: t()
  def new(%SimpleChordParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()

    %{
      stagger_mbeats: params.stagger_mbeats,
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

  def render(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %SimpleChordParams{} = params = machine_params!(opts)

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

    midi_notes = ChordSpec.to_midi_notes(chord_spec)
    note_count = length(midi_notes)

    # Cap stagger to a frame-aligned maximum so all note durations stay non-negative
    # and both length modes can still honor chord-end alignment.
    effective_stagger_mbeats =
      effective_stagger_mbeats(stagger_mbeats, chord_duration_mbeats, note_count, frame_mbeats)

    note_length_mode = normalize_note_length_mode(params.note_length_mode)

    notes =
      build_notes(
        midi_notes,
        sample_start_mbeat,
        effective_stagger_mbeats,
        chord_duration_mbeats,
        note_length_mode,
        sample_context,
        params
      )

    duration_mbeats =
      case notes do
        [] -> chord_duration_mbeats
        _ -> notes |> Enum.map(&(&1.delay_mbeats + &1.adsr.total_mbeats)) |> Enum.max()
      end

    duration_ms = SampleContext.mbeats_to_ms(sample_context, duration_mbeats)
    granularity_ms = SampleContext.mbeats_to_ms(sample_context, frame_mbeats)

    %Performance{
      bpm: sample_context.bpm,
      time_signature: sample_context.time_signature,
      granularity_ms: granularity_ms,
      duration_ms: duration_ms,
      music: build_music(notes, duration_mbeats, sample_context, frame_mbeats)
    }
  end

  defp build_notes(
         midi_notes,
         sample_start_mbeat,
         stagger_mbeats,
         chord_duration_mbeats,
         note_length_mode,
         sample_context,
         %SimpleChordParams{} = params
       ) do
    note_count = length(midi_notes)

    midi_notes
    |> Enum.with_index()
    |> Enum.map(fn {note_number, note_index} ->
      {note_name, octave} = ChordSpec.note_name(note_number)
      note_delay_mbeats = note_index * stagger_mbeats
      note_start_mbeat = sample_start_mbeat + note_delay_mbeats

      note_duration_mbeats =
        note_duration_mbeats(
          chord_duration_mbeats,
          stagger_mbeats,
          note_index,
          note_count,
          note_length_mode
        )

      adsr = build_adsr(note_duration_mbeats, sample_context, params)

      %{
        note_name: note_name,
        octave: octave,
        note: note_number,
        channel: nil,
        velocity: @velocity,
        machine_id: id(),
        chord_instance_id: 0,
        event_index: note_index,
        delay_mbeats: note_start_mbeat,
        adsr: adsr
      }
    end)
  end

  defp build_adsr(
         note_duration_mbeats,
         %SampleContext{} = sample_context,
         %SimpleChordParams{} = params
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

  defp build_music(notes, duration_mbeats, sample_context, frame_mbeats) do
    for at_mbeat <- 0..duration_mbeats//frame_mbeats do
      at_ms = SampleContext.mbeats_to_ms(sample_context, at_mbeat)

      %{
        at_ms: at_ms,
        at_mbeat: at_mbeat,
        notes: Enum.map(notes, &note_frame(&1, at_mbeat))
      }
    end
  end

  defp note_frame(note, at_mbeat) when at_mbeat < note.delay_mbeats do
    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: :pending,
      note_on: false,
      note_off: false,
      pressure: 0,
      bend: 0.0,
      slide: 0
    }
  end

  defp note_frame(note, at_mbeat)
       when at_mbeat > note.delay_mbeats + note.adsr.total_mbeats do
    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: :ended,
      note_on: false,
      note_off: false,
      pressure: 0,
      bend: 0.0,
      slide: 0
    }
  end

  defp note_frame(note, at_mbeat) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    phase = ADSR.phase_at_mbeat(note.adsr, local_elapsed_mbeats)

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: phase,
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.adsr.total_mbeats,
      pressure:
        ADSR.level_at_mbeat(note.adsr, local_elapsed_mbeats) |> then(&(&1 * 127)) |> clamp_7bit(),
      bend: 0.0,
      slide: 0
    }
  end

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %SimpleChordParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(SimpleChordParams)} in :machine_params, got #{inspect(other)}"

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

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.SimpleChord do
  alias Mensch.Machines.SimpleChord

  def id(_machine), do: SimpleChord.id()

  def controls(%SimpleChord{params: params}) do
    %{
      stagger_mbeats: params.stagger_mbeats,
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

  def render(%SimpleChord{params: params}, chord_spec, sample_context, timeline_context, opts) do
    SimpleChord.render(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
