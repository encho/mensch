defmodule Mensch.Modulation.Lfo do
  @moduledoc """
  Shared LFO normalization and sampling helpers.
  """

  alias Mensch.LfoParams
  alias Mensch.SampleContext

  @spec normalize!(LfoParams.t() | map() | nil, keyword()) :: LfoParams.t()
  def normalize!(lfo_params, opts \\ [])

  def normalize!(nil, _opts), do: LfoParams.default()

  def normalize!(%LfoParams{} = lfo_params, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo params")

    %LfoParams{
      curve: normalize_curve!(lfo_params.curve, field_name),
      scale: normalize_scale!(lfo_params.scale, field_name),
      cycles_per_bar: normalize_cycles_per_bar!(lfo_params.cycles_per_bar, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_params.shift_mbeats, field_name),
      polarity: normalize_polarity!(lfo_params.polarity, field_name),
      time_base: normalize_time_base!(lfo_params.time_base, field_name),
      mode: normalize_mode!(lfo_params.mode, field_name)
    }
  end

  def normalize!(lfo_params, opts) when is_map(lfo_params) do
    LfoParams.default()
    |> Map.from_struct()
    |> Map.merge(Map.drop(lfo_params, [:__struct__]))
    |> then(&struct!(LfoParams, &1))
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo params")

    raise ArgumentError,
          "#{field_name} must be #{inspect(LfoParams)}, got: #{inspect(other)}"
  end

  @spec value_at_mbeat(LfoParams.t(), integer(), SampleContext.t(), integer()) :: float()
  def value_at_mbeat(
        %LfoParams{} = lfo_params,
        at_mbeat,
        %SampleContext{} = sample_context,
        entry_start_mbeat_abs
      )
      when is_integer(at_mbeat) and is_integer(entry_start_mbeat_abs) do
    value_at_mbeat(lfo_params, at_mbeat, sample_context, entry_start_mbeat_abs, at_mbeat)
  end

  @spec value_at_mbeat(LfoParams.t(), integer(), SampleContext.t(), integer(), integer()) ::
          float()
  def value_at_mbeat(
        %LfoParams{} = lfo_params,
        at_mbeat,
        %SampleContext{} = sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(entry_start_mbeat_abs) and
             is_integer(note_local_mbeat) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)

    timeline_mbeat =
      case lfo_params.time_base do
        :sample -> entry_start_mbeat_abs + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_params.shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * lfo_params.cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_params.curve
    |> waveform_value(cycle_phase)
    |> apply_polarity(lfo_params)
  end

  @spec apply_to_pressure(float(), float(), LfoParams.t()) :: integer()
  def apply_to_pressure(adsr_level, lfo_norm, %LfoParams{mode: :additive, scale: scale}) do
    normalized = adsr_level + lfo_norm * adsr_level * scale
    clamp_7bit(normalized * 127)
  end

  def apply_to_pressure(adsr_level, lfo_norm, %LfoParams{mode: :multiplicative, scale: scale}) do
    normalized = adsr_level * (1 + lfo_norm * adsr_level * scale)
    clamp_7bit(normalized * 127)
  end

  @spec apply_additive_to_7bit(non_neg_integer(), float(), LfoParams.t()) :: integer()
  def apply_additive_to_7bit(baseline_7bit, lfo_unipolar, %LfoParams{scale: scale}) do
    normalized = baseline_7bit / 127 + lfo_unipolar * scale
    clamp_7bit(normalized * 127)
  end

  @spec apply_additive_to_bend(float(), float(), LfoParams.t()) :: float()
  def apply_additive_to_bend(baseline_bend, lfo_value, %LfoParams{scale: scale}) do
    (baseline_bend + lfo_value * scale)
    |> clamp_bend()
  end

  defp waveform_value(:sine, cycle_phase), do: :math.sin(2 * :math.pi() * cycle_phase)
  defp waveform_value(:triangle, cycle_phase), do: 1.0 - 4.0 * abs(cycle_phase - 0.5)
  defp waveform_value(:saw_up, cycle_phase), do: cycle_phase
  defp waveform_value(:saw_down, cycle_phase), do: -cycle_phase
  defp waveform_value(:square, cycle_phase), do: if(cycle_phase < 0.5, do: 1.0, else: -1.0)

  defp apply_polarity(value, %LfoParams{polarity: :bipolar}), do: value

  defp apply_polarity(value, %LfoParams{polarity: :unipolar}) do
    value
    |> waveform_to_unipolar()
    |> clamp_0_1()
  end

  defp waveform_to_unipolar(value), do: (value + 1.0) / 2.0

  defp clamp_0_1(value), do: value |> max(0.0) |> min(1.0)

  defp normalize_curve!(curve, _field_name)
       when curve in [:sine, :triangle, :saw_up, :saw_down, :square],
       do: curve

  defp normalize_curve!(:sin, _field_name), do: :sine
  defp normalize_curve!(:saw, _field_name), do: :saw_up

  defp normalize_curve!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.curve must be one of :sine, :triangle, :saw_up, :saw_down, :square, got: #{inspect(other)}"
  end

  defp normalize_scale!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_scale!(value, _field_name) when is_float(value), do: value

  defp normalize_scale!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.scale must be a number, got: #{inspect(other)}"
  end

  defp normalize_cycles_per_bar!(value, _field_name) when is_integer(value) and value > 0,
    do: value * 1.0

  defp normalize_cycles_per_bar!(value, _field_name) when is_float(value) and value > 0,
    do: value

  defp normalize_cycles_per_bar!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.cycles_per_bar must be > 0, got: #{inspect(other)}"
  end

  defp normalize_shift_mbeats!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_shift_mbeats!(value, _field_name) when is_float(value), do: value

  defp normalize_shift_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.shift_mbeats must be a number, got: #{inspect(other)}"
  end

  defp normalize_polarity!(polarity, _field_name) when polarity in [:bipolar, :unipolar],
    do: polarity

  defp normalize_polarity!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.polarity must be :bipolar or :unipolar, got: #{inspect(other)}"
  end

  defp normalize_time_base!(time_base, _field_name)
       when time_base in [:sample, :chord, :note],
       do: time_base

  defp normalize_time_base!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.time_base must be :sample, :chord, or :note, got: #{inspect(other)}"
  end

  defp normalize_mode!(mode, _field_name) when mode in [:additive, :multiplicative], do: mode

  defp normalize_mode!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.mode must be :additive or :multiplicative, got: #{inspect(other)}"
  end

  defp clamp_7bit(value), do: value |> round() |> max(0) |> min(127)
  defp clamp_bend(value), do: value |> max(-1.0) |> min(1.0)
end
