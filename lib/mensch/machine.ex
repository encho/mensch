defmodule Mensch.Machine do
  @moduledoc """
  Behaviour for machines: they define HOW a resolved chord is played,
  turning it into domain-level performance events.

  A machine never talks to MIDI/MPE directly — it only produces
  `Mensch.Performance.Event` structs, positioned in beats via the
  `context` it is given.
  """

  alias Mensch.Harmony.ResolvedChord
  alias Mensch.Performance.Event

  @typedoc "At minimum, where (in beats) and how long the chord occupies."
  @type context :: %{start_beat: float(), duration_beats: float()}

  @callback generate(
              resolved_chord :: ResolvedChord.t(),
              machine :: struct(),
              context :: context()
            ) ::
              [Event.t()]
end
