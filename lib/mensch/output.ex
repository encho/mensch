defmodule Mensch.Output do
  @moduledoc """
  The chosen output mode for a project. Real MIDI/MPE sending is not
  implemented yet — this only records the user's intent.
  """

  defstruct mode: :midi

  @type mode :: :midi | :mpe
  @type t :: %__MODULE__{mode: mode()}
end
