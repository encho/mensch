defmodule Mensch.Machines.DynamicVoicingParams do
  @moduledoc """
  Typed parameters for `Mensch.Machines.DynamicVoicing`.

  Parameter reference:

  * `direction`: Inversion motion direction (`:up`, `:down`, `{:cycle_up, n}`,
    or `{:cycle_down, n}` where `n` is the number of full bounce cycles).
  * `number_of_inversions`: For `:up`/`:down`, total number of voicings to
    play, including the first/base voicing. For cycle modes, total voicing
    states in each up/down leg including both endpoints (start and turnaround),
    so `4` means four visible states per leg. Must be >= 2 in cycle modes.
    If requested voicings do not fit the chord duration frame budget,
    validation fails with an error.
  * `lfo_pressure`: Pressure modulation lane config represented as
    `%{lfo: lfo_term, mode: :add | :multiply}`.
    DynamicVoicing first computes a per-note pressure baseline using
    `LfoEnvelope`, then applies this lane to that baseline.
  * `lfo_slide`: Slide (CC74) modulation lane config represented as
    `%{lfo: lfo_term, mode: :add | :multiply}`.
  * `lfo_bend`: Bend modulation lane config represented as
    `%{lfo: lfo_term, mode: :add | :multiply}`.
  * `envelope_attack_mbeats`: Per-note pressure envelope attack duration.
  * `envelope_decay_mbeats`: Per-note pressure envelope decay duration.
  * `envelope_release_mbeats`: Per-note pressure envelope release duration.

  Hold is computed as `note.duration_mbeats - (attack + decay + release)`.
  If this would be negative for a note, rendering raises.
  """

  alias Mensch.Modulation
  alias Mensch.Modulation.LfoCurve
  alias Mensch.Modulation.LfoGroup

  @type direction :: :up | :down | {:cycle_up, pos_integer()} | {:cycle_down, pos_integer()}

  @type modulation_lane :: Modulation.lfo_pressure()
  @type non_neg_number :: non_neg_integer() | float()

  @type t :: %__MODULE__{
          direction: direction(),
          number_of_inversions: pos_integer(),
          lfo_pressure: modulation_lane(),
          lfo_slide: modulation_lane(),
          lfo_bend: modulation_lane(),
          envelope_attack_mbeats: non_neg_number(),
          envelope_decay_mbeats: non_neg_number(),
          envelope_release_mbeats: non_neg_number()
        }

  @enforce_keys [:direction, :number_of_inversions]
  defstruct [
    :direction,
    :number_of_inversions,
    envelope_attack_mbeats: 0.0,
    envelope_decay_mbeats: 0.0,
    envelope_release_mbeats: 0.0,
    lfo_pressure: %{lfo: %LfoGroup{initial: %LfoCurve{}}, mode: :add},
    lfo_slide: %{lfo: %LfoGroup{initial: %LfoCurve{}}, mode: :add},
    lfo_bend: %{lfo: %LfoGroup{initial: %LfoCurve{}}, mode: :add}
  ]

  @doc "Default parameters for the dynamic voicing machine."
  @spec default() :: t()
  def default do
    %__MODULE__{
      direction: :up,
      number_of_inversions: 4,
      envelope_attack_mbeats: 0.0,
      envelope_decay_mbeats: 0.0,
      envelope_release_mbeats: 0.0,
      lfo_pressure: %{lfo: LfoGroup.default(), mode: :add},
      lfo_slide: %{lfo: LfoGroup.default(), mode: :add},
      lfo_bend: %{lfo: LfoGroup.default(), mode: :add}
    }
  end
end
