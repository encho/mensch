defmodule Mensch.NewModulation.LfoCurve do
  @moduledoc """
  Curve-based LFO source.

  The waveform output is mapped into `[min_value, max_value]`.
  """

  alias Mensch.SampleContext

  @type curve :: :sine | :triangle | :square
  @type anchor :: :sample | :chord | :note

  @type t :: %__MODULE__{
          curve: curve(),
          min_value: float(),
          max_value: float(),
          cycles_per_bar: float(),
          shift_mbeats: number(),
          anchor: anchor()
        }

  defstruct curve: :sine,
            min_value: 0.0,
            max_value: 0.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            anchor: :sample

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_curve, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_curve, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo curve")

    %__MODULE__{
      curve: normalize_curve!(lfo_curve.curve, field_name),
      min_value: normalize_value!(lfo_curve.min_value, field_name, :min_value),
      max_value: normalize_value!(lfo_curve.max_value, field_name, :max_value),
      cycles_per_bar: normalize_cycles_per_bar!(lfo_curve.cycles_per_bar, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_curve.shift_mbeats, field_name),
      anchor: normalize_anchor!(lfo_curve.anchor, field_name)
    }
  end

  def normalize!(lfo_curve, opts) when is_map(lfo_curve) do
    lfo_curve
    |> symbolize_map_keys()
    |> then(fn attrs -> struct!(__MODULE__, Map.merge(Map.from_struct(default()), attrs)) end)
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo curve")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  @spec value_at_mbeat(t(), integer(), SampleContext.t(), integer(), integer()) :: float()
  def value_at_mbeat(
        %__MODULE__{} = lfo_curve,
        at_mbeat,
        %SampleContext{} = sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(entry_start_mbeat_abs) and
             is_integer(note_local_mbeat) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)

    timeline_mbeat =
      case lfo_curve.anchor do
        :sample -> entry_start_mbeat_abs + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_curve.shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * lfo_curve.cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_curve.curve
    |> waveform_value(cycle_phase)
    |> map_to_range(lfo_curve.min_value, lfo_curve.max_value)
  end

  defp waveform_value(:sine, cycle_phase), do: :math.sin(2 * :math.pi() * cycle_phase)
  defp waveform_value(:triangle, cycle_phase), do: 1.0 - 4.0 * abs(cycle_phase - 0.5)
  defp waveform_value(:square, cycle_phase), do: if(cycle_phase < 0.5, do: 1.0, else: -1.0)

  defp map_to_range(value, min_value, max_value) do
    normalized = (value + 1.0) / 2.0
    min_value + normalized * (max_value - min_value)
  end

  defp normalize_curve!(curve, _field_name)
       when curve in [:sine, :triangle, :square],
       do: curve

  defp normalize_curve!(:sin, _field_name), do: :sine

  defp normalize_curve!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.curve must be one of :sine, :triangle, :square, got: #{inspect(other)}"
  end

  defp normalize_value!(value, _field_name, _value_name) when is_integer(value), do: value * 1.0
  defp normalize_value!(value, _field_name, _value_name) when is_float(value), do: value

  defp normalize_value!(other, field_name, value_name) do
    raise ArgumentError,
          "#{field_name}.#{value_name} must be a number, got: #{inspect(other)}"
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

  defp normalize_anchor!(anchor, _field_name)
       when anchor in [:sample, :chord, :note],
       do: anchor

  defp normalize_anchor!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.anchor must be :sample, :chord, or :note, got: #{inspect(other)}"
  end

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"curve", value} -> {:curve, value}
      {"min_value", value} -> {:min_value, value}
      {"max_value", value} -> {:max_value, value}
      {"cycles_per_bar", value} -> {:cycles_per_bar, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      pair -> pair
    end)
    |> Map.new()
    |> maybe_apply_legacy_scale_polarity()
  end

  # Backward compatibility for older maps still using scale/polarity.
  defp maybe_apply_legacy_scale_polarity(attrs) do
    case {Map.get(attrs, :scale), Map.get(attrs, :polarity)} do
      {nil, _} ->
        attrs

      {scale, polarity} when is_integer(scale) or is_float(scale) ->
        scale_f = if(is_integer(scale), do: scale * 1.0, else: scale)

        {min_value, max_value} =
          case polarity do
            :unipolar -> {0.0, scale_f}
            _ -> {-scale_f, scale_f}
          end

        attrs
        |> Map.put_new(:min_value, min_value)
        |> Map.put_new(:max_value, max_value)

      _ ->
        attrs
    end
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoCurve do
  alias Mensch.NewModulation.LfoCurve

  def evaluate(
        %LfoCurve{} = lfo_curve,
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      ) do
    lfo_curve
    |> LfoCurve.normalize!(field_name: "lfo curve")
    |> LfoCurve.value_at_mbeat(at_mbeat, sample_context, entry_start_mbeat_abs, note_local_mbeat)
  end
end
