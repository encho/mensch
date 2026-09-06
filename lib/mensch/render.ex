defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  This keeps a simple entry point (`generate/0`) for the current UI,
  while the real rendering algorithm lives in machine modules and
  consumes explicit `ChordSpec` + `SongContext` + `TimelineContext`.
  Default contexts are provided for convenience.
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

  @doc "Renders the default chord (`C4 maj7`, root position) using the default machine."
  @spec generate() :: Performance.t()
  def generate do
    StrummedMpe.render(@default_spec, @default_song_context, @default_timeline_context)
  end

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
end
