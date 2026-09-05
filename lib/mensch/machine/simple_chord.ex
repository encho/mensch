defmodule Mensch.Machine.SimpleChord do
  @moduledoc """
  Plays every tone of the chord, each with its own copy of the step's
  envelope, gently staggered (a "strum") so notes don't all start in
  perfect unison: each note after the first starts a little further
  behind the previous one, proportional to the envelope's own attack -
  the first note (the emphasis note) always starts right on time.
  """

  @behaviour Mensch.Machine

  alias Mensch.Chord

  # Each successive note starts this fraction of the envelope's own
  # attack further behind the previous one - small enough to read as
  # a "strum", not a conscious delay.
  @stagger_fraction 0.25

  @impl true
  def generate(chord, envelope) do
    chord
    |> Chord.notes()
    |> Enum.with_index()
    |> Enum.map(fn {note, index} ->
      %{
        note: note,
        envelope: envelope,
        delay_bars: index * @stagger_fraction * envelope.attack_bars
      }
    end)
  end
end
