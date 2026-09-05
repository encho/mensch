defmodule Mensch.Machine.RootNoteMpe do
  @moduledoc """
  ROOT_NOTE_MPE: plays the chord's root note exactly like ROOT_NOTE,
  but also emits simple per-note MPE-style expression (pressure and
  pitch bend) while the note sounds.

  The expression oscillates several times across the sounding
  duration — pitch bend as a bipolar vibrato (wobbling above and below
  the note) and pressure as a pumping pulse (0 up to full depth and
  back, repeatedly) — so the modulation is clearly audible as movement
  rather than a single gentle swell. This is not a real-time
  modulation engine, just a pure, testable timeline of
  `Mensch.Performance.Event`s. The machine never talks to MIDI/MPE
  directly.
  """

  @behaviour Mensch.Machine

  alias Mensch.Performance.Event

  defstruct octave: 3,
            velocity: 90,
            note_length: 1.0,
            pressure_depth: 0.8,
            pitch_bend_depth: 1.0,
            modulation_steps: 16,
            modulation_cycles: 2

  @type t :: %__MODULE__{
          octave: non_neg_integer(),
          velocity: 0..127,
          note_length: float(),
          pressure_depth: float(),
          pitch_bend_depth: float(),
          modulation_steps: pos_integer(),
          modulation_cycles: pos_integer()
        }

  @impl true
  def generate(resolved_chord, %__MODULE__{} = machine, %{
        start_beat: start_beat,
        duration_beats: duration_beats
      }) do
    note = {resolved_chord.root, machine.octave}
    sounding_beats = duration_beats * machine.note_length
    note_off_beat = start_beat + sounding_beats

    [%Event{type: :note_on, at_beat: start_beat, note: note, velocity: machine.velocity}] ++
      expression_events(note, start_beat, sounding_beats, machine) ++
      [%Event{type: :note_off, at_beat: note_off_beat, note: note}]
  end

  defp expression_events(_note, _start_beat, _sounding_beats, %__MODULE__{modulation_steps: steps})
       when steps < 2,
       do: []

  defp expression_events(note, start_beat, sounding_beats, %__MODULE__{} = machine) do
    cycles = machine.modulation_cycles

    1..(machine.modulation_steps - 1)
    |> Enum.flat_map(fn step ->
      phase = step / machine.modulation_steps
      at_beat = start_beat + phase * sounding_beats
      angle = phase * 2 * :math.pi() * cycles
      # bipolar wobble: swings above and below the note, several times
      pitch_wave = :math.sin(angle)
      # unipolar pulse: pumps from 0 up to full depth and back, several times
      pressure_wave = (1 - :math.cos(angle)) / 2

      [
        %Event{
          type: :pressure,
          at_beat: at_beat,
          note: note,
          value: pressure_wave * machine.pressure_depth
        },
        %Event{
          type: :pitch_bend,
          at_beat: at_beat,
          note: note,
          value: pitch_wave * machine.pitch_bend_depth
        }
      ]
    end)
  end
end
