defmodule Mensch.Modulation.LfoSaw do
  @moduledoc """
  Saw-specific LFO source with configurable cycle timing.

  Parameters:

  - `curve` (`:saw_up | :saw_down`): Saw direction. `:saw_up` ramps upward and
    drops, `:saw_down` ramps downward and jumps back.
  - `peak_value` (`number`): Absolute peak endpoint of the ramp.
  - `baseline_value` (`number`): Baseline endpoint used at reset/start. Defaults
    to `0`.
  - `cycle_length_in_mbeats` (`number > 0`): Duration of one full saw cycle in
    millibeats.
  - `shift_mbeats` (`number`): Phase offset in millibeats.
  - `sleep_duration_mbeats` (`number >= 0`): Duration of each cycle spent at
    `baseline_value` before the saw starts moving.
  - `anchor` (`:sample | :chord | :note`): Time reference for phase:
    - `:sample` uses absolute sample timeline.
    - `:chord` resets phase at chord start.
    - `:note` resets phase per note lifecycle.
  - `saw_duration_mbeats` (`number > 0`): Ramp duration in each cycle before
    the abrupt reset. Must satisfy
    `sleep_duration_mbeats + saw_duration_mbeats <= cycle_length_in_mbeats`.

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
          cycle_length_in_mbeats: float(),
          shift_mbeats: number(),
          sleep_duration_mbeats: float(),
          anchor: anchor(),
          saw_duration_mbeats: float()
        }

  defstruct curve: :saw_up,
            peak_value: 0.0,
            baseline_value: 0.0,
            cycle_length_in_mbeats: 4000.0,
            shift_mbeats: 0.0,
            sleep_duration_mbeats: 0.0,
            anchor: :sample,
            saw_duration_mbeats: 4000.0

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
      cycle_length_in_mbeats:
        normalize_cycle_length_in_mbeats!(
          lfo_saw.cycle_length_in_mbeats,
          field_name
        ),
      shift_mbeats: normalize_shift_mbeats!(lfo_saw.shift_mbeats, field_name),
      sleep_duration_mbeats:
        normalize_sleep_duration_mbeats!(
          lfo_saw.sleep_duration_mbeats,
          field_name
        ),
      anchor: normalize_anchor!(lfo_saw.anchor, field_name),
      saw_duration_mbeats:
        normalize_saw_duration_mbeats!(
          lfo_saw.saw_duration_mbeats,
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
        %SampleContext{} = _sample_context,
        absolute_chord_start_mbeat,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(absolute_chord_start_mbeat) and
             is_integer(note_local_mbeat) do
    timeline_mbeat =
      case lfo_saw.anchor do
        :sample -> absolute_chord_start_mbeat + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat + lfo_saw.shift_mbeats

    cycle_position_mbeats =
      shifted_mbeat -
        :math.floor(shifted_mbeat / lfo_saw.cycle_length_in_mbeats) *
          lfo_saw.cycle_length_in_mbeats

    lfo_saw.curve
    |> waveform_value(
      cycle_position_mbeats,
      lfo_saw.sleep_duration_mbeats,
      lfo_saw.saw_duration_mbeats
    )
    |> interpolate(lfo_saw.baseline_value, lfo_saw.peak_value)
  end

  defp waveform_value(
         :saw_up,
         cycle_position_mbeats,
         sleep_duration_mbeats,
         saw_duration_mbeats
       )
       when cycle_position_mbeats >= sleep_duration_mbeats and
              cycle_position_mbeats < sleep_duration_mbeats + saw_duration_mbeats,
       do: (cycle_position_mbeats - sleep_duration_mbeats) / saw_duration_mbeats

  defp waveform_value(
         :saw_up,
         _cycle_position_mbeats,
         _sleep_duration_mbeats,
         _saw_duration_mbeats
       ),
       do: 0.0

  defp waveform_value(
         :saw_down,
         cycle_position_mbeats,
         sleep_duration_mbeats,
         saw_duration_mbeats
       )
       when cycle_position_mbeats >= sleep_duration_mbeats and
              cycle_position_mbeats < sleep_duration_mbeats + saw_duration_mbeats,
       do: 1.0 - (cycle_position_mbeats - sleep_duration_mbeats) / saw_duration_mbeats

  defp waveform_value(
         :saw_down,
         _cycle_position_mbeats,
         _sleep_duration_mbeats,
         _saw_duration_mbeats
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

  defp normalize_cycle_length_in_mbeats!(value, _field_name)
       when is_integer(value) and value > 0,
       do: value * 1.0

  defp normalize_cycle_length_in_mbeats!(value, _field_name)
       when is_float(value) and value > 0,
       do: value

  defp normalize_cycle_length_in_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.cycle_length_in_mbeats must be > 0, got: #{inspect(other)}"
  end

  defp normalize_shift_mbeats!(value, _field_name) when is_integer(value), do: value * 1.0
  defp normalize_shift_mbeats!(value, _field_name) when is_float(value), do: value

  defp normalize_shift_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.shift_mbeats must be a number, got: #{inspect(other)}"
  end

  defp normalize_sleep_duration_mbeats!(value, _field_name) when is_integer(value),
    do: normalize_sleep_duration_mbeats!(value * 1.0, "")

  defp normalize_sleep_duration_mbeats!(value, _field_name)
       when is_float(value) and value >= 0,
       do: value

  defp normalize_sleep_duration_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.sleep_duration_mbeats must be >= 0, got: #{inspect(other)}"
  end

  defp normalize_anchor!(anchor, _field_name)
       when anchor in [:sample, :chord, :note],
       do: anchor

  defp normalize_anchor!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.anchor must be :sample, :chord, or :note, got: #{inspect(other)}"
  end

  defp normalize_saw_duration_mbeats!(value, _field_name) when is_integer(value),
    do: normalize_saw_duration_mbeats!(value * 1.0, "")

  defp normalize_saw_duration_mbeats!(value, _field_name)
       when is_float(value) and value > 0,
       do: value

  defp normalize_saw_duration_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.saw_duration_mbeats must be > 0, got: #{inspect(other)}"
  end

  defp validate_phase_window!(%__MODULE__{} = lfo_saw, field_name) do
    if lfo_saw.sleep_duration_mbeats + lfo_saw.saw_duration_mbeats <=
         lfo_saw.cycle_length_in_mbeats do
      lfo_saw
    else
      raise ArgumentError,
            "#{field_name}.sleep_duration_mbeats + #{field_name}.saw_duration_mbeats must be <= #{field_name}.cycle_length_in_mbeats, got: #{inspect(lfo_saw.sleep_duration_mbeats + lfo_saw.saw_duration_mbeats)} > #{inspect(lfo_saw.cycle_length_in_mbeats)}"
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
      {"cycle_length_in_mbeats", value} -> {:cycle_length_in_mbeats, value}
      {:cycle_length_in_mbeats, value} -> {:cycle_length_in_mbeats, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"sleep_duration_mbeats", value} -> {:sleep_duration_mbeats, value}
      {:sleep_duration_mbeats, value} -> {:sleep_duration_mbeats, value}
      {"sleep_duration_cycle_perc", value} -> {:sleep_duration_mbeats, value}
      {:sleep_duration_cycle_perc, value} -> {:sleep_duration_mbeats, value}
      {"sleep_phase", value} -> {:sleep_duration_mbeats, value}
      {:sleep_phase, value} -> {:sleep_duration_mbeats, value}
      {"sleep", value} -> {:sleep_duration_mbeats, value}
      {:sleep, value} -> {:sleep_duration_mbeats, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      {"saw_duration_mbeats", value} -> {:saw_duration_mbeats, value}
      {:saw_duration_mbeats, value} -> {:saw_duration_mbeats, value}
      {"saw_duration_cycle_perc", value} -> {:saw_duration_mbeats, value}
      {:saw_duration_cycle_perc, value} -> {:saw_duration_mbeats, value}
      {"drop_phase", value} -> {:saw_duration_mbeats, value}
      {:drop_phase, value} -> {:saw_duration_mbeats, value}
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
