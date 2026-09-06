defmodule Mensch.Machine do
  @moduledoc """
  Behavior for algorithmic chord performers ("machines").

  A machine turns a `Mensch.ChordSpec` (musical intent) into a
  precomputed `%Mensch.Performance{}` timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Performance

  @callback id() :: atom()
  @callback controls() :: map()
  @callback render(ChordSpec.t(), keyword()) :: Performance.t()
end
