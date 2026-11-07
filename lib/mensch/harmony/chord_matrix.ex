defmodule Mensch.Harmony.ChordMatrix do
  @moduledoc """
  Matrix abstraction with explicit row and column counts.
  """

  @enforce_keys [:number_rows, :number_columns]
  defstruct [:number_rows, :number_columns]

  @type t :: %__MODULE__{
          number_rows: pos_integer(),
          number_columns: pos_integer()
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(%{} = attrs) do
    with {:ok, number_rows} <- parse_positive_integer(Map.get(attrs, :number_rows)),
         {:ok, number_columns} <- parse_positive_integer(Map.get(attrs, :number_columns)) do
      {:ok, %__MODULE__{number_rows: number_rows, number_columns: number_columns}}
    end
  end

  def new(_attrs), do: {:error, :invalid_chord_matrix}

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(_value), do: {:error, :invalid_dimension}
end
