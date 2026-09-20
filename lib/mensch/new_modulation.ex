defmodule Mensch.NewModulation do
  @moduledoc """
  Shared helpers for the new modulation architecture.
  """

  alias Mensch.NewModulation.LfoCurve
  alias Mensch.NewModulation.LfoGroup
  alias Mensch.NewModulation.LfoRamp
  alias Mensch.NewModulation.LfoSaw

  @type lfo_term :: LfoCurve.t() | LfoSaw.t() | LfoRamp.t() | LfoGroup.t()
  @type mode :: :add | :multiply
  @type lfo_pressure :: %{lfo: lfo_term(), mode: mode()}

  # Canonicalize incoming lfo_pressure config to a strict internal shape.
  # Accepts atom or string keys, normalizes the nested lfo term, and validates mode.
  @spec normalize_lfo_pressure!(lfo_pressure() | map(), String.t()) :: lfo_pressure()
  def normalize_lfo_pressure!(lfo_pressure, field_name \\ "lfo_pressure")

  def normalize_lfo_pressure!(%{lfo: lfo, mode: mode}, field_name) do
    %{
      lfo: LfoGroup.normalize_term!(lfo, "#{field_name}.lfo"),
      mode: normalize_mode!(mode, field_name)
    }
  end

  def normalize_lfo_pressure!(lfo_pressure, field_name) when is_map(lfo_pressure) do
    attrs = symbolize_lfo_pressure_keys(lfo_pressure)
    normalize_lfo_pressure!(attrs, field_name)
  end

  def normalize_lfo_pressure!(other, field_name) do
    raise ArgumentError,
          "#{field_name} must be %{lfo: lfo_term, mode: :add | :multiply}, got: #{inspect(other)}"
  end

  @spec apply_to_pressure(non_neg_integer(), float(), mode()) :: integer()
  def apply_to_pressure(baseline_7bit, modulation_value, :add) do
    clamp_7bit(baseline_7bit + modulation_value)
  end

  def apply_to_pressure(baseline_7bit, modulation_value, :multiply) do
    clamp_7bit(baseline_7bit * (1 + modulation_value))
  end

  # Keep mode checks centralized so all machines share identical validation errors.
  defp normalize_mode!(mode, _field_name) when mode in [:add, :multiply], do: mode

  defp normalize_mode!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.mode must be :add or :multiply, got: #{inspect(other)}"
  end

  # Accept either atom-keyed or string-keyed external maps.
  defp symbolize_lfo_pressure_keys(lfo_pressure) do
    lfo = Map.get(lfo_pressure, :lfo, Map.get(lfo_pressure, "lfo"))
    mode = Map.get(lfo_pressure, :mode, Map.get(lfo_pressure, "mode"))
    %{lfo: lfo, mode: mode}
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
end
