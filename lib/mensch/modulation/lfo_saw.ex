defmodule Mensch.Modulation.LfoSaw do
  @moduledoc """
  Saw-specific LFO source with configurable cycle timing.

  Parameters:

  - `curve` (`:saw_up | :saw_down`): Saw direction. `:saw_up` ramps upward and
    drops, `:saw_down` ramps downward and jumps back.
  - `peak_value` (`number`): Absolute peak endpoint of the ramp.
  - `baseline_value` (`number`): Baseline endpoint used at reset/start. Defaults
    to `0`.
  - `cycles_per_bar` (`number > 0`): Oscillation speed in cycles per bar.
  - `shift_mbeats` (`number`): Phase offset in millibeats.
  - `sleep_duration_cycle_perc` (`0 <= number < 1`): Fraction of each cycle spent at
    `baseline_value` before the saw starts moving.
  - `anchor` (`:sample | :chord | :note`): Time reference for phase:
    - `:sample` uses absolute sample timeline.
    - `:chord` resets phase at chord start.
    - `:note` resets phase per note lifecycle.
  - `saw_duration_cycle_perc` (`0 < number <= 1`): Fraction of each cycle used for the
    ramp before the abrupt reset. For example, `0.75` means ramp for 75% of
    the cycle and reset during the remaining 25%. Must satisfy
    `sleep_duration_cycle_perc + saw_duration_cycle_perc <= 1`.

  Notes:

  - This module implements `Mensch.Modulation.Lfo` via the protocol impl at
    the bottom of this file.
  - `normalize!/2` accepts both struct and map inputs and validates all
    parameters.
  """

  alias Mensch.SampleContext

  @type curve :: :saw_up | :saw_down
  @type anchor :: :sample | :chord | :note

  @type t :: %__MODULE__{
          curve: curve(),
          peak_value: float(),
          baseline_value: float(),
          cycles_per_bar: float(),
          shift_mbeats: number(),
          sleep_duration_cycle_perc: float(),
          anchor: anchor(),
          saw_duration_cycle_perc: float()
        }

  defstruct curve: :saw_up,
            peak_value: 0.0,
            baseline_value: 0.0,
            cycles_per_bar: 1.0,
            shift_mbeats: 0.0,
            sleep_duration_cycle_perc: 0.0,
            anchor: :sample,
            saw_duration_cycle_perc: 1.0

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_saw, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_saw, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo saw")

    %__MODULE__{
      curve: normalize_curve!(lfo_saw.curve, field_name),
      peak_value: normalize_peak_value!(lfo_saw.peak_value, field_name),
      baseline_value: normalize_baseline_value!(lfo_saw.baseline_value, field_name),
      cycles_per_bar: normalize_cycles_per_bar!(lfo_saw.cycles_per_bar, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_saw.shift_mbeats, field_name),
      sleep_duration_cycle_perc:
        normalize_sleep_duration_cycle_perc!(
          lfo_saw.sleep_duration_cycle_perc,
          field_name
        ),
      anchor: normalize_anchor!(lfo_saw.anchor, field_name),
      saw_duration_cycle_perc:
        normalize_saw_duration_cycle_perc!(
          lfo_saw.saw_duration_cycle_perc,
          field_name
        )
    }
    |> validate_phase_window!(field_name)
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
        absolute_chord_start_mbeat,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(absolute_chord_start_mbeat) and
             is_integer(note_local_mbeat) do
    mbeats_per_bar = SampleContext.mbeats_per_bar(sample_context)

    timeline_mbeat =
      case lfo_saw.anchor do
        :sample -> absolute_chord_start_mbeat + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_saw.shift_mbeats
    phase = shifted_mbeat / mbeats_per_bar * lfo_saw.cycles_per_bar
    cycle_phase = phase - :math.floor(phase)

    lfo_saw.curve
    |> waveform_value(
      cycle_phase,
      lfo_saw.sleep_duration_cycle_perc,
      lfo_saw.saw_duration_cycle_perc
    )
    |> interpolate(lfo_saw.baseline_value, lfo_saw.peak_value)
  end

  defp waveform_value(
         :saw_up,
         cycle_phase,
         sleep_duration_cycle_perc,
         saw_duration_cycle_perc
       )
       when cycle_phase >= sleep_duration_cycle_perc and
              cycle_phase < sleep_duration_cycle_perc + saw_duration_cycle_perc,
       do: (cycle_phase - sleep_duration_cycle_perc) / saw_duration_cycle_perc

  defp waveform_value(
         :saw_up,
         _cycle_phase,
         _sleep_duration_cycle_perc,
         _saw_duration_cycle_perc
       ),
       do: 0.0

  defp waveform_value(
         :saw_down,
         cycle_phase,
         sleep_duration_cycle_perc,
         saw_duration_cycle_perc
       )
       when cycle_phase >= sleep_duration_cycle_perc and
              cycle_phase < sleep_duration_cycle_perc + saw_duration_cycle_perc,
       do: 1.0 - (cycle_phase - sleep_duration_cycle_perc) / saw_duration_cycle_perc

  defp waveform_value(
         :saw_down,
         _cycle_phase,
         _sleep_duration_cycle_perc,
         _saw_duration_cycle_perc
       ),
       do: 0.0

  defp interpolate(progress, min_value, max_value) do
    min_value + progress * (max_value - min_value)
  end

  defp normalize_curve!(curve, _field_name) when curve in [:saw_up, :saw_down], do: curve
  defp normalize_curve!(:saw, _field_name), do: :saw_up

  defp normalize_curve!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.curve must be :saw_up or :saw_down, got: #{inspect(other)}"
  end

  defp normalize_peak_value!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_peak_value!(value, _field_name) when is_float(value), do: value

  defp normalize_peak_value!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.peak_value must be a number, got: #{inspect(other)}"
  end

  defp normalize_baseline_value!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_baseline_value!(value, _field_name) when is_float(value), do: value

  defp normalize_baseline_value!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.baseline_value must be a number, got: #{inspect(other)}"
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

  defp normalize_sleep_duration_cycle_perc!(value, _field_name) when is_integer(value),
    do: normalize_sleep_duration_cycle_perc!(value * 1.0, "")

  defp normalize_sleep_duration_cycle_perc!(value, _field_name)
       when is_float(value) and value >= 0 and value < 1,
       do: value

  defp normalize_sleep_duration_cycle_perc!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.sleep_duration_cycle_perc must be >= 0 and < 1, got: #{inspect(other)}"
  end

  defp normalize_anchor!(anchor, _field_name)
       when anchor in [:sample, :chord, :note],
       do: anchor

  defp normalize_anchor!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.anchor must be :sample, :chord, or :note, got: #{inspect(other)}"
  end

  defp normalize_saw_duration_cycle_perc!(value, _field_name) when is_integer(value),
    do: normalize_saw_duration_cycle_perc!(value * 1.0, "")

  defp normalize_saw_duration_cycle_perc!(value, _field_name)
       when is_float(value) and value > 0 and value <= 1,
       do: value

  defp normalize_saw_duration_cycle_perc!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.saw_duration_cycle_perc must be > 0 and <= 1, got: #{inspect(other)}"
  end

  defp validate_phase_window!(%__MODULE__{} = lfo_saw, field_name) do
    if lfo_saw.sleep_duration_cycle_perc + lfo_saw.saw_duration_cycle_perc <= 1.0 do
      lfo_saw
    else
      raise ArgumentError,
            "#{field_name}.sleep_duration_cycle_perc + #{field_name}.saw_duration_cycle_perc must be <= 1, got: #{inspect(lfo_saw.sleep_duration_cycle_perc + lfo_saw.saw_duration_cycle_perc)}"
    end
  end

  defp symbolize_map_keys(map) do
    map
    |> Enum.map(fn
      {"curve", value} -> {:curve, value}
      {"peak_value", value} -> {:peak_value, value}
      {"scale", value} -> {:peak_value, value}
      {:scale, value} -> {:peak_value, value}
      {"baseline_value", value} -> {:baseline_value, value}
      {"baseline", value} -> {:baseline_value, value}
      {:baseline, value} -> {:baseline_value, value}
      {"cycles_per_bar", value} -> {:cycles_per_bar, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"sleep_duration_cycle_perc", value} -> {:sleep_duration_cycle_perc, value}
      {:sleep_duration_cycle_perc, value} -> {:sleep_duration_cycle_perc, value}
      {"sleep_phase", value} -> {:sleep_duration_cycle_perc, value}
      {:sleep_phase, value} -> {:sleep_duration_cycle_perc, value}
      {"sleep", value} -> {:sleep_duration_cycle_perc, value}
      {:sleep, value} -> {:sleep_duration_cycle_perc, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      {"saw_duration_cycle_perc", value} -> {:saw_duration_cycle_perc, value}
      {:saw_duration_cycle_perc, value} -> {:saw_duration_cycle_perc, value}
      {"drop_phase", value} -> {:saw_duration_cycle_perc, value}
      {:drop_phase, value} -> {:saw_duration_cycle_perc, value}
      pair -> pair
    end)
    |> Map.new()
  end
end

defimpl Mensch.Modulation.Lfo, for: Mensch.Modulation.LfoSaw do
  alias Mensch.Modulation.LfoSaw

  def evaluate(
        %LfoSaw{} = lfo_saw,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        note_local_mbeat
      ) do
    lfo_saw
    |> LfoSaw.normalize!(field_name: "lfo saw")
    |> LfoSaw.value_at_mbeat(
      at_mbeat,
      sample_context,
      absolute_chord_start_mbeat,
      note_local_mbeat
    )
  end
end
