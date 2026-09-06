defmodule Mensch.Machine do
  @moduledoc """
  Behavior for algorithmic chord performers ("machines").

  A machine turns:

    * `Mensch.ChordSpec` (harmonic intent)
    * `Mensch.SampleContext` (global timing, bpm/ppq/signature)
    * `Mensch.TimelineContext` (where/for how long on the sample grid)

  into a precomputed `%Mensch.Performance{}` timeline.
  """

  alias Mensch.ChordSpec
  alias Mensch.Performance
  alias Mensch.SampleContext
  alias Mensch.TimelineContext

  @callback id() :: atom()
  @callback controls() :: map()
  @callback render(ChordSpec.t(), SampleContext.t(), TimelineContext.t(), keyword()) ::
              Performance.t()
end
