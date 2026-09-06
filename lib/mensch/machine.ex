defmodule Mensch.Machine do
  @moduledoc """
  Behavior for algorithmic chord performers ("machines").

  A machine turns a `Mensch.ChordSpec` (musical intent) into a
  precomputed `%Mensch.Performance{}` timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Performance
  alias Mensch.SongContext
  alias Mensch.TimelineContext

  @callback id() :: atom()
  @callback controls() :: map()
  @callback render(ChordSpec.t(), SongContext.t(), TimelineContext.t(), keyword()) ::
              Performance.t()
end
