defmodule Mensch.SampleDefinition.Provider do
  @moduledoc """
  Behaviour for sample definition provider modules.
  """

  alias Mensch.SampleDefinition

  @callback sample(pos_integer()) :: SampleDefinition.t()
end
