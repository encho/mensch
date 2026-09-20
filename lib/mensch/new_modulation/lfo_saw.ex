defmodule Mensch.NewModulation.LfoSaw do
  @moduledoc """
  Saw-specific LFO source with configurable drop point.

  `drop_phase` controls when the abrupt reset happens in the cycle.
  For example, `drop_phase: 0.75` means the ramp runs through 75% of the
  cycle and then drops for the remaining 25%.
  """

  alias Mensch.SampleContext

  @type curve :: :saw_up | :saw_down
  @type polarity :: :bipolar | :unipolar
  @type anchor :: :sample | :chord | :note

  @type t :: %__MODULE__{
          curve: curve(),
          scale: float(),
          cycles_per_bar: float(),
          shift_mbeats: number(),
          polarity: polarity(),
          anchor: anchor(),
          drop_phase: float()
        }

  defstruct curve: :saw_up,
            scale: 0.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            polarity: :bipolar,
            anchor: :sample,
            drop_phase: 1.0

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_saw, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_saw, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo saw")

    %__MODULE__{
      curve: normalize_curve!(lfo_saw.curve, field_name),
      scale: normalize_scale!(lfo_saw.scale, field_name),
      cycles_per_bar: normalize_cycles_per_bar!(lfo_saw.cycles_per_bar, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_saw.shift_mbeats, field_name),
      polarity: normalize_polarity!(lfo_saw.polarity, field_name),
      anchor: normalize_anchor!(lfo_saw.anchor, field_name),
      drop_phase: normalize_drop_phase!(lfo_saw.drop_phase, field_name)
    }
  end

  def normalize!(lfo_saw, opts) when is_map(lfo_saw) do
    lfo_saw
    |> symbolize_map_keys()
    |> then(fn attrs -> struct!(__MODULE__, Map.merge(Map.from_struct(default()), attrs)) end)
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo saw")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  @spec value_at_mbeat(t(), integer(), SampleContext.t(), integer(), integer()) :: float()
  def value_at_mbeat(
        %__MODULE__{} = lfo_saw,
        at_mbeat,
        %SampleContext{} = sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(entry_start_mbeat_abs) and
             is_integer(note_local_mbeat) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)

    timeline_mbeat =
      case lfo_saw.anchor do
        :sample -> entry_start_mbeat_abs + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_saw.shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * lfo_saw.cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_saw.curve
    |> waveform_value(cycle_phase, lfo_saw.drop_phase)
    |> apply_polarity(lfo_saw)
    |> Kernel.*(lfo_saw.scale)
  end

  defp waveform_value(:saw_up, cycle_phase, drop_phase) when cycle_phase < drop_phase,
    do: cycle_phase / drop_phase

  defp waveform_value(:saw_up, _cycle_phase, _drop_phase), do: 0.0

  defp waveform_value(:saw_down, cycle_phase, drop_phase) when cycle_phase < drop_phase,
    do: -(cycle_phase / drop_phase)

  defp waveform_value(:saw_down, _cycle_phase, _drop_phase), do: 0.0

  defp apply_polarity(value, %__MODULE__{polarity: :bipolar}), do: value

  defp apply_polarity(value, %__MODULE__{polarity: :unipolar}) do
    value
    |> waveform_to_unipolar()
    |> clamp_0_1()
  end

  defp waveform_to_unipolar(value), do: (value + 1.0) / 2.0
  defp clamp_0_1(value), do: value |> max(0.0) |> min(1.0)

  defp normalize_curve!(curve, _field_name) when curve in [:saw_up, :saw_down], do: curve
  defp normalize_curve!(:saw, _field_name), do: :saw_up

  defp normalize_curve!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.curve must be :saw_up or :saw_down, got: #{inspect(other)}"
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

  defp normalize_anchor!(anchor, _field_name)
       when anchor in [:sample, :chord, :note],
       do: anchor

  defp normalize_anchor!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.anchor must be :sample, :chord, or :note, got: #{inspect(other)}"
  end

  defp normalize_drop_phase!(value, _field_name) when is_integer(value),
    do: normalize_drop_phase!(value * 1.0, "")

  defp normalize_drop_phase!(value, _field_name)
       when is_float(value) and value > 0 and value <= 1,
       do: value

  defp normalize_drop_phase!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.drop_phase must be > 0 and <= 1, got: #{inspect(other)}"
  end

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"curve", value} -> {:curve, value}
      {"scale", value} -> {:scale, value}
      {"cycles_per_bar", value} -> {:cycles_per_bar, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"polarity", value} -> {:polarity, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      {"drop_phase", value} -> {:drop_phase, value}
      pair -> pair
    end)
    |> Map.new()
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoSaw do
  alias Mensch.NewModulation.LfoSaw

  def evaluate(
        %LfoSaw{} = lfo_saw,
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      ) do
    lfo_saw
    |> LfoSaw.normalize!(field_name: "lfo saw")
    |> LfoSaw.value_at_mbeat(at_mbeat, sample_context, entry_start_mbeat_abs, note_local_mbeat)
  end
end
