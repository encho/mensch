defmodule Mensch.Machines.StrummedMpe do
  @moduledoc """
  First concrete machine implementation.

  Renders a strummed, per-note-envelope MPE performance from a generic
  `Mensch.ChordSpec`.

  Frame stepping comes from the global sample context and is resolved to
  millibeats per render, so frame timing stays tempo-aware and musically aligned.
  Note provenance is flat on each note event via `machine_id` and
  `chord_instance_id`.
  """

  alias Mensch.ChordSpec
  alias Mensch.Envelope.ADSR
  alias Mensch.Machines.StrummedMpeParams
  alias Mensch.NoteShape
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @type t :: %__MODULE__{params: StrummedMpeParams.t()}

  @enforce_keys [:params]
  defstruct [:params]

  def id, do: :strummed_mpe

  def params_module, do: StrummedMpeParams

  def default_params, do: StrummedMpeParams.default()

  @spec new(StrummedMpeParams.t()) :: t()
  def new(%StrummedMpeParams{} = params), do: %__MODULE__{params: params}

  @spec new() :: t()
  def new, do: %__MODULE__{params: default_params()}

  def controls do
    params = default_params()
    %{note_stagger_mbeats: params.note_stagger_mbeats}
  end

  def render(
        %ChordSpec{} = chord_spec,
        %SampleContext{} = sample_context,
        %TimelineContext{} = timeline_context,
        opts \\ []
      ) do
    %StrummedMpeParams{} = params = machine_params!(opts)

    frame_mbeats = SampleContext.frame_units(sample_context)

    note_stagger_mbeats =
      params.note_stagger_mbeats
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

    chord_end_mbeat = sample_start_mbeat + chord_duration_mbeats

    notes =
      build_notes(
        chord_spec,
        sample_start_mbeat,
        note_stagger_mbeats,
        chord_end_mbeat,
        sample_context,
        params
      )

    duration_mbeats =
      notes |> Enum.map(&(&1.delay_mbeats + &1.adsr.total_mbeats)) |> Enum.max()

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
         chord_spec,
         sample_start_mbeat,
         note_stagger_mbeats,
         chord_end_mbeat,
         sample_context,
         %StrummedMpeParams{} = params
       ) do
    chord_notes = ChordSpec.to_midi_notes(chord_spec)
    note_count = max(length(chord_notes), 1)

    chord_notes
    |> Enum.with_index()
    |> Enum.map(fn {note_number, note_index} ->
      note_delay_mbeats = note_index * note_stagger_mbeats
      note_start_mbeat = sample_start_mbeat + note_delay_mbeats
      note_duration_mbeats = max(chord_end_mbeat - note_start_mbeat, 0)
      {note_name, octave} = ChordSpec.note_name(note_number)

      adsr = build_adsr(note_duration_mbeats, sample_context, params)

      %{
        note_name: note_name,
        octave: octave,
        note: note_number,
        channel: nil,
        velocity: params.velocity,
        phase_offset: note_index / note_count * 2 * :math.pi(),
        emphasis: note_index == 0,
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
         %StrummedMpeParams{} = params
       ) do
    ADSR.from_mbeats(note_duration_mbeats, sample_context, %{
      attack_mbeats: params.attack_mbeats,
      decay_mbeats: params.decay_mbeats,
      release_mbeats: params.release_mbeats
    })
  end

  defp build_music(notes, duration_mbeats, sample_context, frame_mbeats) do
    for at_mbeat <- 0..duration_mbeats//frame_mbeats do
      at_ms = SampleContext.mbeats_to_ms(sample_context, at_mbeat)

      %{
        at_ms: at_ms,
        at_mbeat: at_mbeat,
        notes: Enum.map(notes, &note_frame(&1, at_mbeat, sample_context))
      }
    end
  end

  defp machine_params!(opts) do
    case Keyword.fetch(opts, :machine_params) do
      {:ok, %StrummedMpeParams{} = params} ->
        params

      {:ok, other} ->
        raise ArgumentError,
              "expected #{inspect(StrummedMpeParams)} in :machine_params, got #{inspect(other)}"

      :error ->
        raise ArgumentError, "missing :machine_params for #{inspect(__MODULE__)}"
    end
  end

  defp note_frame(note, at_mbeat, _sample_context) when at_mbeat < note.delay_mbeats do
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

  defp note_frame(note, at_mbeat, _sample_context)
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

  defp note_frame(note, at_mbeat, sample_context) do
    local_elapsed_mbeats = at_mbeat - note.delay_mbeats
    local_elapsed_ms = SampleContext.mbeats_to_ms(sample_context, local_elapsed_mbeats)

    %{
      note_name: note.note_name,
      octave: note.octave,
      note: note.note,
      channel: note.channel,
      velocity: note.velocity,
      machine_id: note.machine_id,
      chord_instance_id: note.chord_instance_id,
      event_index: note.event_index,
      phase: NoteShape.phase_at(note.adsr, local_elapsed_mbeats),
      note_on: local_elapsed_mbeats == 0,
      note_off: local_elapsed_mbeats == note.adsr.total_mbeats,
      pressure:
        NoteShape.pressure(note.adsr, note.phase_offset, local_elapsed_mbeats, local_elapsed_ms)
        |> clamp_7bit(),
      bend: NoteShape.bend(note.adsr, note.phase_offset, local_elapsed_ms, local_elapsed_mbeats),
      slide:
        NoteShape.slide(
          note.adsr,
          note.phase_offset,
          note.emphasis,
          local_elapsed_ms,
          local_elapsed_mbeats
        )
        |> clamp_7bit()
    }
  end

  defp snap_mbeats(mbeats, mbeats_per_frame),
    do: round(mbeats / mbeats_per_frame) * mbeats_per_frame

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end

defimpl Mensch.Machine, for: Mensch.Machines.StrummedMpe do
  alias Mensch.Machines.StrummedMpe

  def id(_machine), do: StrummedMpe.id()

  def controls(%StrummedMpe{params: params}) do
    %{
      note_stagger_mbeats: params.note_stagger_mbeats
    }
  end

  def render(%StrummedMpe{params: params}, chord_spec, sample_context, timeline_context, opts) do
    StrummedMpe.render(
      chord_spec,
      sample_context,
      timeline_context,
      Keyword.put(opts, :machine_params, params)
    )
  end
end
