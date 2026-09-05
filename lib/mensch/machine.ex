defmodule Mensch.Machine do
  @moduledoc """
  A machine decides which of a chord's tones actually sound and what
  individual envelope (and optional start stagger) each of those notes
  gets, for a given `%Mensch.Chord{}` and step `%Mensch.Envelope{}`.

  `Mensch.ChordPlayer` just starts one `Mensch.NotePlayer` per entry a
  machine hands back - it has no opinion of its own about which notes
  to play or how to shape their envelopes. This is the seam for future
  strategies (arpeggios, bass lines, humanized voicings, ...) without
  `ChordPlayer` ever needing to change.

  Selectable per chord/step in the UI (see `options/0`).
  """

  alias Mensch.Chord
  alias Mensch.Envelope

  @type note_plan :: %{note: atom(), envelope: Envelope.t(), delay_bars: number()}

  @doc """
  Given a chord and the step's envelope, returns a list of
  `%{note:, envelope:, delay_bars:}` maps - one entry per
  `Mensch.NotePlayer` to start. `delay_bars` staggers a note's actual
  start (see `Mensch.NotePlayer`'s `:start_delay_ms`) - `0` starts
  immediately, alongside the chord itself.
  """
  @callback generate(Chord.t(), Envelope.t()) :: [note_plan()]

  @machines %{
    simple_chord: Mensch.Machine.SimpleChord,
    root_note: Mensch.Machine.RootNote
  }

  @doc "Machine ids and display labels, selectable in the UI, in display order."
  def options, do: [{"Simple Chord", :simple_chord}, {"Root Note", :root_note}]

  @doc "The default machine id, used when none is otherwise specified."
  def default, do: :simple_chord

  @doc "Generates the note plan for `machine_id` (one of `options/0`'s values)."
  def generate(machine_id, %Chord{} = chord, %Envelope{} = envelope) do
    Map.fetch!(@machines, machine_id).generate(chord, envelope)
  end
end
