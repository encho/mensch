defmodule Mensch.Machine.RootNote do
  @moduledoc """
  Plays only the chord's root, with the step's envelope unmodified and
  no start delay - a single `Mensch.NotePlayer` instead of one per
  chord tone.
  """

  @behaviour Mensch.Machine

  alias Mensch.Chord

  @impl true
  def generate(chord, envelope) do
    [%{note: Chord.root(chord), envelope: envelope, delay_bars: 0}]
  end
end
