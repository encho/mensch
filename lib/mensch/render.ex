defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  `generate/0` is intentionally self-contained (single chord starting
  at time zero) for chord auditioning.

  Use `generate_song/0` or `generate_song/2` to render and aggregate a
  full multi-entry song timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Performance
  alias Mensch.SongContext
  alias Mensch.TimelineContext
  alias Mensch.BeatPosition

  @default_spec %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}
  @default_song_context %SongContext{bpm: 120, time_signature: {4, 4}, ppq: 96}
  @default_timeline_context %TimelineContext{
    start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
    duration_ticks: 384
  }

  @default_song_entries [
    %{
      chord_spec: %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 0, beat: 0, tick: 0},
        duration_ticks: 384
      },
      machine_module: StrummedMpe
    },
    %{
      chord_spec: %ChordSpec{root: :d, modifier: :min7, octave: 4, inversion: 0},
      timeline_context: %TimelineContext{
        start_beat: %BeatPosition{bar: 1, beat: 0, tick: 0},
        duration_ticks: 384
      },
      machine_module: StrummedMpe
    }
  ]

  @doc "Renders the default chord (`C4 maj7`, root position) using the default machine."
  @spec generate() :: Performance.t()
  def generate do
    StrummedMpe.render(@default_spec, @default_song_context, @default_timeline_context)
  end

  @doc "Default multi-entry song render (aggregated timeline)."
  @spec generate_song() :: Performance.t()
  def generate_song do
    generate_song(@default_song_entries, @default_song_context)
  end

  @doc "Renders and aggregates a full song timeline from entry maps."
  @spec generate_song([map()], SongContext.t()) :: Performance.t()
  def generate_song(entries, %SongContext{} = song_context) when is_list(entries) do
    entries
    |> Enum.map(fn %{chord_spec: chord_spec, timeline_context: timeline_context} = entry ->
      machine_module = Map.get(entry, :machine_module, StrummedMpe)
      machine_module.render(chord_spec, song_context, timeline_context)
    end)
    |> merge_performances(song_context)
  end

  @doc "Returns the default song entries for UI/debug display."
  @spec default_song_entries() :: [map()]
  def default_song_entries, do: @default_song_entries

  @doc "Returns the default song context used by `generate/0` and `generate_song/0`."
  @spec default_song_context() :: SongContext.t()
  def default_song_context, do: @default_song_context

  @doc "Renders the given chord spec using default song/timeline contexts."
  @spec generate(ChordSpec.t()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec) do
    StrummedMpe.render(chord_spec, @default_song_context, @default_timeline_context)
  end

  @doc "Renders a chord spec with an explicit song/timeline context via the default machine."
  @spec generate(ChordSpec.t(), SongContext.t(), TimelineContext.t()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context
      ) do
    StrummedMpe.render(chord_spec, song_context, timeline_context)
  end

  @doc "Renders a chord spec via a specific machine module implementing `Mensch.Machine`."
  @spec generate(ChordSpec.t(), SongContext.t(), TimelineContext.t(), module()) :: Performance.t()
  def generate(
        %ChordSpec{} = chord_spec,
        %SongContext{} = song_context,
        %TimelineContext{} = timeline_context,
        machine_module
      )
      when is_atom(machine_module) do
    machine_module.render(chord_spec, song_context, timeline_context)
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {ChordSpec.root(), integer()}
  def note_name(note_number), do: ChordSpec.note_name(note_number)

  defp merge_performances([], %SongContext{} = song_context) do
    %Performance{
      bpm: song_context.bpm,
      time_signature: song_context.time_signature,
      granularity_ms: SongContext.ticks_to_ms(song_context, 6),
      duration_ms: 0,
      music: []
    }
  end

  defp merge_performances(performances, %SongContext{} = song_context) do
    merged_music =
      performances
      |> Enum.flat_map(& &1.music)
      |> Enum.group_by(& &1.at_tick)
      |> Enum.map(fn {at_tick, frames} ->
        %{
          at_tick: at_tick,
          at_ms: SongContext.ticks_to_ms(song_context, at_tick),
          notes: Enum.flat_map(frames, & &1.notes)
        }
      end)
      |> Enum.sort_by(& &1.at_tick)

    %Performance{
      bpm: song_context.bpm,
      time_signature: song_context.time_signature,
      granularity_ms: performances |> Enum.map(& &1.granularity_ms) |> Enum.min(),
      duration_ms: performances |> Enum.map(& &1.duration_ms) |> Enum.max(),
      music: merged_music
    }
  end
end
