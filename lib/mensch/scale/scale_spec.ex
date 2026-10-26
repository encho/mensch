defmodule Mensch.Scale.ScaleSpec do
  @moduledoc """
  Generic, independent scale representation.
  """

  @type family_id :: atom()
  @type pitch_class :: atom()

  @enforce_keys [:tonic, :family, :mode, :name, :intervals]
  defstruct [:tonic, :family, :mode, :name, :intervals]

  @type t :: %__MODULE__{
          tonic: pitch_class(),
          family: family_id(),
          mode: pos_integer() | nil,
          name: String.t(),
          intervals: [integer()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    spec = struct(__MODULE__, attrs)

    with :ok <- validate_tonic(spec.tonic),
         :ok <- validate_name(spec.name),
         :ok <- validate_mode(spec.mode),
         {:ok, intervals} <- normalize_intervals(spec.intervals) do
      {:ok, %{spec | intervals: intervals}}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid scale spec: #{inspect(reason)}"
    end
  end

  @spec normalize_intervals([integer()]) :: {:ok, [integer()]} | {:error, term()}
  def normalize_intervals(intervals) when is_list(intervals) do
    normalized =
      intervals
      |> Enum.filter(&is_integer/1)
      |> Enum.map(&rem(&1 + 120, 12))
      |> Enum.uniq()
      |> Enum.sort()

    cond do
      normalized == [] -> {:error, :empty_intervals}
      Enum.at(normalized, 0) != 0 -> {:error, :intervals_must_start_with_zero}
      true -> {:ok, normalized}
    end
  end

  def normalize_intervals(_), do: {:error, :invalid_intervals}

  defp validate_tonic(value) when is_atom(value), do: :ok
  defp validate_tonic(_), do: {:error, :invalid_tonic}

  defp validate_name(value) when is_binary(value) and value != "", do: :ok
  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_mode(nil), do: :ok
  defp validate_mode(value) when is_integer(value) and value > 0, do: :ok
  defp validate_mode(_), do: {:error, :invalid_mode}
end
