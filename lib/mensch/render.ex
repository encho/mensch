defmodule Mensch.Render do
  @moduledoc """
  Facade that renders a performance via a concrete `Mensch.Machine`.

  This keeps a simple entry point (`generate/0`) for the current UI,
  while the real rendering algorithm lives in machine modules.
  """

  alias Mensch.ChordSpec
  alias Mensch.Machines.StrummedMpe
  alias Mensch.Performance

  @default_spec %ChordSpec{root: :c, modifier: :maj7, octave: 4, inversion: 0}

  @doc "Renders the default chord (`C4 maj7`, root position) using the default machine."
  @spec generate() :: Performance.t()
  def generate do
    StrummedMpe.render(@default_spec)
  end

  @doc "Renders the given chord spec using the default machine."
  @spec generate(ChordSpec.t()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec) do
    StrummedMpe.render(chord_spec)
  end

  @doc "Renders a chord spec via a specific machine module implementing `Mensch.Machine`."
  @spec generate(ChordSpec.t(), module()) :: Performance.t()
  def generate(%ChordSpec{} = chord_spec, machine_module) when is_atom(machine_module) do
    machine_module.render(chord_spec)
  end

  @doc "The note name and octave for a MIDI note number, e.g. `64` -> `{:e, 4}`."
  @spec note_name(integer()) :: {ChordSpec.root(), integer()}
  def note_name(note_number), do: ChordSpec.note_name(note_number)
end
