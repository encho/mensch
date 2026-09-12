defmodule Mensch.Machine.VoicingStrategy do
  @moduledoc """
  Behavior for chord-voicing strategies.

  A voicing strategy turns a `Mensch.ChordSpec` into an ordered list of voiced
  notes. The output defines what notes are played and in which sequence order.

  Timing is intentionally excluded from this stage and is assigned later by the
  machine timing policy.
  """

  alias Mensch.ChordSpec

  @type voiced_note :: %{
          midi_note: integer(),
          degree_index: non_neg_integer(),
          event_index: non_neg_integer()
        }

  @callback build_voiced_notes(strategy :: struct(), chord_spec :: ChordSpec.t()) :: [
              voiced_note()
            ]
end
