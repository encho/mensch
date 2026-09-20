defmodule Mensch.NewModulation.LfoRamp do
  @moduledoc """
  Non-cyclic ramp LFO source.

  Unlike oscillator-style LFOs, this source does not wrap. It interpolates from
  `start_value` to `end_value` over `span_mbeats`, then holds `end_value`.

  `span_mbeats` is the ramp duration in millibeats. Example: `4000` means the
  transition completes over one 4/4 bar.

  Positive `shift_mbeats` delays ramp start; negative values start earlier.
  """

  alias Mensch.SampleContext

  @type interpolation_function :: :linear | :ease_in | :ease_out | :ease_in_out
  @type anchor :: :sample | :chord | :note

  @type t :: %__MODULE__{
          start_value: float(),
          end_value: float(),
          interpolation_function: interpolation_function(),
          span_mbeats: float(),
          shift_mbeats: float(),
          anchor: anchor()
        }

  defstruct start_value: 0.0,
            end_value: 1.0,
            interpolation_function: :linear,
            span_mbeats: 4000.0,
            shift_mbeats: 0.0,
            anchor: :note

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_ramp, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_ramp, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo ramp")

    %__MODULE__{
      start_value: normalize_value!(lfo_ramp.start_value, field_name, :start_value),
      end_value: normalize_value!(lfo_ramp.end_value, field_name, :end_value),
      interpolation_function:
        normalize_interpolation_function!(lfo_ramp.interpolation_function, field_name),
      span_mbeats: normalize_span_mbeats!(lfo_ramp.span_mbeats, field_name),
      shift_mbeats: normalize_shift_mbeats!(lfo_ramp.shift_mbeats, field_name),
      anchor: normalize_anchor!(lfo_ramp.anchor, field_name)
    }
  end

  def normalize!(lfo_ramp, opts) when is_map(lfo_ramp) do
    lfo_ramp
    |> symbolize_map_keys()
    |> then(fn attrs -> struct!(__MODULE__, Map.merge(Map.from_struct(default()), attrs)) end)
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo ramp")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  @spec value_at_mbeat(t(), integer(), SampleContext.t(), integer(), integer()) :: float()
  def value_at_mbeat(
        %__MODULE__{} = lfo_ramp,
        at_mbeat,
        %SampleContext{} = _sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(entry_start_mbeat_abs) and
             is_integer(note_local_mbeat) do
    timeline_mbeat =
      case lfo_ramp.anchor do
        :sample -> entry_start_mbeat_abs + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    # Positive shift delays the ramp start by moving the effective timeline back.
    shifted_mbeat = timeline_mbeat - lfo_ramp.shift_mbeats
    progress = (shifted_mbeat / lfo_ramp.span_mbeats) |> clamp_0_1()
    shaped_progress = apply_interpolation(progress, lfo_ramp.interpolation_function)

    lfo_ramp.start_value + (lfo_ramp.end_value - lfo_ramp.start_value) * shaped_progress
  end

  defp apply_interpolation(progress, :linear), do: progress
  defp apply_interpolation(progress, :ease_in), do: progress * progress
  defp apply_interpolation(progress, :ease_out), do: 1.0 - :math.pow(1.0 - progress, 2)

  defp apply_interpolation(progress, :ease_in_out) when progress < 0.5,
    do: 2.0 * progress * progress

  defp apply_interpolation(progress, :ease_in_out),
    do: 1.0 - :math.pow(-2.0 * progress + 2.0, 2) / 2.0

  defp clamp_0_1(value), do: value |> max(0.0) |> min(1.0)

  defp normalize_value!(value, _field_name, _value_name) when is_integer(value), do: value * 1.0
  defp normalize_value!(value, _field_name, _value_name) when is_float(value), do: value

  defp normalize_value!(other, field_name, value_name) do
    raise ArgumentError,
          "#{field_name}.#{value_name} must be a number, got: #{inspect(other)}"
  end

  defp normalize_interpolation_function!(function, _field_name)
       when function in [:linear, :ease_in, :ease_out, :ease_in_out],
       do: function

  defp normalize_interpolation_function!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.interpolation_function must be :linear, :ease_in, :ease_out, or :ease_in_out, got: #{inspect(other)}"
  end

  defp normalize_span_mbeats!(value, _field_name) when is_integer(value) and value > 0,
    do: value * 1.0

  defp normalize_span_mbeats!(value, _field_name) when is_float(value) and value > 0,
    do: value

  defp normalize_span_mbeats!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.span_mbeats must be > 0, got: #{inspect(other)}"
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
      {"start_value", value} -> {:start_value, value}
      {"end_value", value} -> {:end_value, value}
      {"interpolation_function", value} -> {:interpolation_function, value}
      {"span_mbeats", value} -> {:span_mbeats, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      pair -> pair
    end)
    |> Map.new()
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoRamp do
  alias Mensch.NewModulation.LfoRamp

  def evaluate(
        %LfoRamp{} = lfo_ramp,
        at_mbeat,
        sample_context,
        entry_start_mbeat_abs,
        note_local_mbeat
      ) do
    lfo_ramp
    |> LfoRamp.normalize!(field_name: "lfo ramp")
    |> LfoRamp.value_at_mbeat(at_mbeat, sample_context, entry_start_mbeat_abs, note_local_mbeat)
  end
end
