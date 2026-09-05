defmodule Mensch.Machine.RootNote do
  @moduledoc """
  The ROOT_NOTE machine: it ignores every chord tone except the root,
  and plays that root as a single sustained note for (a fraction of)
  the chord's duration.

      Dm7   -> D3
      G7    -> G3
      Cmaj7 -> C3

  """

  @behaviour Mensch.Machine

  alias Mensch.Performance.Event

  defstruct octave: 3, velocity: 90, note_length: 1.0

  @type t :: %__MODULE__{
          octave: non_neg_integer(),
          velocity: 0..127,
          note_length: float()
        }

  @impl true
  def generate(resolved_chord, %__MODULE__{} = machine, %{
        start_beat: start_beat,
        duration_beats: duration_beats
      }) do
    note = {resolved_chord.root, machine.octave}
    note_off_beat = start_beat + duration_beats * machine.note_length

    [
      %Event{type: :note_on, at_beat: start_beat, note: note, velocity: machine.velocity},
      %Event{type: :note_off, at_beat: note_off_beat, note: note}
    ]
  end
end
