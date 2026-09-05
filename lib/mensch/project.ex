defmodule Mensch.Project do
  @moduledoc """
  The current composition/performance configuration: tempo, key, chord
  duration, progression, performance machine, and output mode.

  This is plain, editable configuration data — the LiveView owns and
  mutates it directly; harmony resolution and performance generation
  are pure functions applied to it on demand (e.g. when PLAY is
  clicked), not stored on the struct itself.
  """

  alias Mensch.Harmony.{ChordSpec, Key}
  alias Mensch.Machine.RootNote
  alias Mensch.Output

  defstruct [:bpm, :key, :chord_duration, :progression, :machine, :output]

  @type t :: %__MODULE__{
          bpm: pos_integer(),
          key: Key.t(),
          chord_duration: {:beats, number()},
          progression: [ChordSpec.t()],
          machine: struct(),
          output: Output.t()
        }

  @doc """
  Builds the default project: 120 BPM, C Major, 4 beats/chord,
  ii7 -> V7 -> Imaj7, ROOT_NOTE, MIDI.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      bpm: 120,
      key: %Key{root: :c, scale: :major},
      chord_duration: {:beats, 4},
      progression: [
        %ChordSpec{degree: :ii, modifier: :min7},
        %ChordSpec{degree: :V, modifier: :dom7},
        %ChordSpec{degree: :I, modifier: :maj7}
      ],
      machine: %RootNote{octave: 3, velocity: 90, note_length: 1.0},
      output: %Output{mode: :midi}
    }
  end
end
