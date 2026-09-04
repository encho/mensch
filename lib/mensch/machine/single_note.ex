defmodule Mensch.Machine.SingleNote do
  @moduledoc """
  The SINGLE_NOTE machine: produces exactly one musical note per Note
  Trig.

  A SINGLE_NOTE machine does not own harmonic state; it consumes a
  `Mensch.HarmonicContext` to resolve its `pitch` (a scale degree in
  Scale mode, or a direct note class in Chromatic mode) into a sounding
  note.
  """

  alias Mensch.HarmonicContext
  alias Mensch.Scale

  defstruct pitch: {:degree, 1},
            octave: 4,
            duration: {:beats, 1.0},
            velocity: 80,
            pressure: 0.5,
            aftertouch: 0.0,
            pitch_offset: 0.0,
            release: {:beats, 0.25}

  @type musical_time :: {:beats, number()}
  @type pitch :: {:degree, integer()} | {:note, Scale.note_class()}

  @type t :: %__MODULE__{
          pitch: pitch(),
          octave: integer(),
          duration: musical_time(),
          velocity: 0..127,
          pressure: float(),
          aftertouch: float(),
          pitch_offset: float(),
          release: musical_time()
        }

  @doc "Builds a SINGLE_NOTE machine with its default parameters."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Resolves the sounding note name (e.g. `"E4"`) from a Harmonic Context
  and this machine's pitch/octave, honoring Scale vs Chromatic mode.
  """
  @spec resolve_note(HarmonicContext.t(), t()) :: String.t()
  def resolve_note(%HarmonicContext{mode: :chromatic}, %__MODULE__{
        pitch: {:note, note_class},
        octave: octave
      }) do
    Scale.note_name(note_class, octave)
  end

  def resolve_note(%HarmonicContext{mode: :scale, root: root, scale: scale}, %__MODULE__{
        pitch: {:degree, degree},
        octave: octave
      }) do
    {note_class, octave_shift} = Scale.degree_to_note(root, scale, degree)
    Scale.note_name(note_class, octave + octave_shift)
  end
end
