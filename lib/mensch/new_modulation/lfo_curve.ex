defmodule Mensch.NewModulation.LfoCurve do
  @moduledoc """
  Curve-based LFO source.

  `scale` multiplies the waveform output directly.
  """

  alias Mensch.SampleContext

  @type curve :: :sine | :triangle | :saw_up | :saw_down | :square
  @type polarity :: :bipolar | :unipolar
  @type time_base :: :sample | :chord | :note

  @type t :: %__MODULE__{
          curve: curve(),
          scale: float(),
          cycles_per_bar: float(),
          shift_mbeats: number(),
          polarity: polarity(),
          time_base: time_base()
        }

  defstruct curve: :sine,
            scale: 0.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            polarity: :bipolar,
            time_base: :sample

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_curve, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_curve, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo curve")

    %__MODULE__{
      curve: normalize_curve!(lfo_curve.curve, field_name),
      scale: normalize_scale!(lfo_curve.scale, field_name),
      cycles_per_bar: normalize_cycles_per_bar!(lfo_curve.cycles_per_bar, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_curve.shift_mbeats, field_name),
      polarity: normalize_polarity!(lfo_curve.polarity, field_name),
      time_base: normalize_time_base!(lfo_curve.time_base, field_name)
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
      case lfo_curve.time_base do
        :sample -> entry_start_mbeat_abs + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_curve.shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * lfo_curve.cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_curve.curve
    |> waveform_value(cycle_phase)
    |> apply_polarity(lfo_curve)
    |> Kernel.*(lfo_curve.scale)
  end

  defp waveform_value(:sine, cycle_phase), do: :math.sin(2 * :math.pi() * cycle_phase)
  defp waveform_value(:triangle, cycle_phase), do: 1.0 - 4.0 * abs(cycle_phase - 0.5)
  defp waveform_value(:saw_up, cycle_phase), do: cycle_phase
  defp waveform_value(:saw_down, cycle_phase), do: -cycle_phase
  defp waveform_value(:square, cycle_phase), do: if(cycle_phase < 0.5, do: 1.0, else: -1.0)

  defp apply_polarity(value, %__MODULE__{polarity: :bipolar}), do: value

  defp apply_polarity(value, %__MODULE__{polarity: :unipolar}) do
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

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"curve", value} -> {:curve, value}
      {"scale", value} -> {:scale, value}
      {"cycles_per_bar", value} -> {:cycles_per_bar, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"polarity", value} -> {:polarity, value}
      {"time_base", value} -> {:time_base, value}
      pair -> pair
    end)
    |> Map.new()
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
