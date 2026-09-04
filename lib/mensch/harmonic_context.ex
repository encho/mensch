defmodule Mensch.HarmonicContext do
  @moduledoc """
  Track-level harmonic defaults.

  A Harmonic Context is either in Scale mode (pitches are expressed as
  scale degrees against a root/scale) or Chromatic mode (pitches are
  expressed as direct note classes). It provides the harmonic frame that
  a Machine (e.g. `Mensch.Machine.SingleNote`) resolves pitch against; it
  does not itself know how to resolve a pitch.
  """

  alias Mensch.Scale

  defstruct mode: :scale, root: :c, scale: :major

  @type mode :: :scale | :chromatic

  @type t :: %__MODULE__{
          mode: mode(),
          root: Scale.note_class(),
          scale: Scale.scale_name()
        }

  @doc "Builds the default Harmonic Context: Scale mode, root C, Major scale."
  @spec new() :: t()
  def new, do: %__MODULE__{}
end
