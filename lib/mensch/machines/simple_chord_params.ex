defmodule Mensch.Machines.SimpleChordParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.SimpleChord`.

  Parameter reference:

  * `stagger_mbeats`: Delay between successive chord tones in millibeats.
  * `voicing_strategy`: Strategy module/params that determines which notes are
    voiced from the chord and in what order.
  * `note_length_mode`: `:equal` for equal note lengths, or `:align_end` so
    all notes end at the chord end.
  * `attack_mbeats`: Envelope attack duration in millibeats.
  * `decay_mbeats`: Envelope decay duration in millibeats.
  * `release_mbeats`: Envelope release duration in millibeats (`0` disables
    release phase and sustains until note-off).
  * `attack_curve`: Attack interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `decay_curve`: Decay interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `release_curve`: Release interpolation (`:linear`, `:exp`, `:log`, `:s_curve`).
  * `peak_level`: Peak envelope level (`0.0..1.0`).
  * `sustain_level`: Sustain envelope level (`0.0..1.0`).
  """

  alias Mensch.Machine.VoicingStrategies.ChordTones
  alias Mensch.Machine.VoicingStrategies.Traversal

  @type curve :: :linear | :exp | :log | :s_curve
  @type note_length_mode :: :equal | :align_end
  @type voicing_strategy :: ChordTones.t() | Traversal.t()

  @type t :: %__MODULE__{
          stagger_mbeats: non_neg_integer(),
          voicing_strategy: voicing_strategy(),
          note_length_mode: note_length_mode(),
          attack_mbeats: non_neg_integer(),
          decay_mbeats: non_neg_integer(),
          release_mbeats: non_neg_integer(),
          attack_curve: curve(),
          decay_curve: curve(),
          release_curve: curve(),
          peak_level: float(),
          sustain_level: float()
        }

  @enforce_keys [
    :stagger_mbeats,
    :voicing_strategy,
    :note_length_mode,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]
  defstruct [
    :stagger_mbeats,
    :voicing_strategy,
    :note_length_mode,
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]

  @doc "Default parameters for the simple chord machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      stagger_mbeats: 120,
      voicing_strategy: ChordTones.new(),
      note_length_mode: :equal,
      attack_mbeats: 80,
      decay_mbeats: 150,
      release_mbeats: 220,
      attack_curve: :linear,
      decay_curve: :linear,
      release_curve: :linear,
      peak_level: 1.0,
      sustain_level: 0.72
    }
  end
end
