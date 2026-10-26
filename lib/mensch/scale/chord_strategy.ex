defmodule Mensch.Scale.ChordStrategy do
  @moduledoc """
  Behaviour for scale-driven chord generation strategies.

  Strategies are intentionally independent from legacy harmony resolvers and
  operate only on `Mensch.Scale.ScaleSpec` data.
  """

  alias Mensch.Scale.ScaleSpec

  @type chord_shape ::
          :triad
          | :seventh
          | :ninth
          | :eleventh
          | :thirteenth
          | :add6
          | :six_nine

  @type generated_chord :: %{
          required(:strategy) => atom(),
          required(:shape) => chord_shape(),
          required(:degree) => pos_integer(),
          required(:root_note) => String.t(),
          required(:root_pitch_class) => integer(),
          required(:note_names) => [String.t()],
          required(:pitch_classes) => [integer()],
          required(:scale_degree_positions) => [pos_integer()],
          required(:scale_intervals_from_tonic) => [integer()]
        }

  @callback id() :: atom()
  @callback label() :: String.t()
  @callback shapes() :: [chord_shape()]

  @callback generate(ScaleSpec.t(), pos_integer(), keyword()) ::
              {:ok, generated_chord()} | {:error, term()}
end
