defmodule Mensch.Performance do
  @moduledoc """
  Canonical shape for a precomputed performance timeline.

  This wraps the rendered data (`bpm`, `time_signature`, `music`, etc.)
  in a dedicated struct and provides analysis helpers so callers do not
  need to re-implement timeline inspection logic.

  Example dataset:

      %Mensch.Performance{
        bpm: 120,
        time_signature: {4, 4},
        granularity_ms: 30,
        duration_ms: 2490,
        music: [
          %{
            at_ms: 0,
            notes: [
              %{note_name: :c, octave: 4, note: 60, channel: 1, velocity: 100,
                phase: :attack, note_on: true, note_off: false,
                pressure: 0, bend: 0.0, slide: 0},
              %{note_name: :e, octave: 4, note: 64, channel: 2, velocity: 100,
                phase: :pending, note_on: false, note_off: false,
                pressure: 0, bend: 0.0, slide: 0}
            ]
          },
          %{
            at_ms: 60,
            notes: [
              %{note_name: :c, octave: 4, note: 60, channel: 1, velocity: 100,
                phase: :attack, note_on: false, note_off: false,
                pressure: 76, bend: 0.0, slide: 0},
              %{note_name: :e, octave: 4, note: 64, channel: 2, velocity: 100,
                phase: :attack, note_on: true, note_off: false,
                pressure: 0, bend: 0.0, slide: 0}
            ]
          }
        ]
      }
  """

  @type note_event :: %{
          at_ms: non_neg_integer(),
          note_name: atom(),
          octave: integer(),
          note: non_neg_integer(),
          channel: non_neg_integer(),
          velocity: non_neg_integer(),
          phase: atom(),
          note_on: boolean(),
          note_off: boolean(),
          pressure: non_neg_integer(),
          bend: float(),
          slide: non_neg_integer()
        }

  @type frame :: %{at_ms: non_neg_integer(), notes: [note_event()]}

  @type t :: %__MODULE__{
          bpm: pos_integer(),
          time_signature: {pos_integer(), pos_integer()},
          granularity_ms: pos_integer(),
          duration_ms: non_neg_integer(),
          music: [frame()]
        }

  @enforce_keys [:bpm, :time_signature, :granularity_ms, :duration_ms, :music]
  defstruct [:bpm, :time_signature, :granularity_ms, :duration_ms, :music]

  @doc "Builds a `#{inspect(__MODULE__)}` from a map with matching keys."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @doc "How many frames the timeline contains."
  @spec frame_count(t()) :: non_neg_integer()
  def frame_count(%__MODULE__{music: music}), do: length(music)

  @doc "Duration in seconds."
  @spec duration_seconds(t()) :: float()
  def duration_seconds(%__MODULE__{duration_ms: duration_ms}), do: duration_ms / 1000

  @doc "Distinct MIDI note numbers present in the performance, ascending."
  @spec distinct_notes(t()) :: [non_neg_integer()]
  def distinct_notes(%__MODULE__{music: music}) do
    music
    |> Enum.flat_map(& &1.notes)
    |> Enum.map(& &1.note)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Lowest/highest MIDI note numbers present in the performance."
  @spec note_range(t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def note_range(performance) do
    case distinct_notes(performance) do
      [] -> nil
      notes -> {hd(notes), List.last(notes)}
    end
  end

  @doc "All note on/off events across all frames, sorted by `at_ms`."
  @spec io_events(t()) :: [map()]
  def io_events(%__MODULE__{music: music}) do
    music
    |> Enum.flat_map(fn frame ->
      Enum.flat_map(frame.notes, fn note ->
        base = %{at_ms: frame.at_ms, note: note.note, channel: note.channel}

        cond do
          note.note_on and note.note_off ->
            [Map.put(base, :type, :on), Map.put(base, :type, :off)]

          note.note_on ->
            [Map.put(base, :type, :on)]

          note.note_off ->
            [Map.put(base, :type, :off)]

          true ->
            []
        end
      end)
    end)
    |> Enum.sort_by(fn event -> {event.at_ms, event.channel, event.note, event.type} end)
  end
end
