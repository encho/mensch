defprotocol Mensch.NewModulation.Lfo do
  @moduledoc """
  Evaluates a modulation source at a given time position.

  Implementations should return a numeric modulation value. The caller decides
  how to apply that value to target parameters.
  """

  @spec evaluate(t(), integer(), Mensch.SampleContext.t(), integer(), integer()) :: float()
  def evaluate(lfo, at_mbeat, sample_context, entry_start_mbeat_abs, note_local_mbeat)
end
