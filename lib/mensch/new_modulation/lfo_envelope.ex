defmodule Mensch.NewModulation.LfoEnvelope do
  @moduledoc """
  Piecewise ADSHR-style envelope modulation source.

  The envelope runs through four time segments after `shift_mbeats`:

  1. attack: `start_value -> peak_value`
  2. decay: `peak_value -> sustain_value`
  3. hold: `sustain_value` (flat)
  4. release: `sustain_value -> end_value`

  After release it holds `end_value`.
  """

  alias Mensch.SampleContext

  @type interpolation_function :: :linear | :ease_in | :ease_out | :ease_in_out
  @type anchor :: :sample | :chord | :note

  @type t :: %__MODULE__{
          start_value: float(),
          peak_value: float(),
          sustain_value: float(),
          end_value: float(),
          attack_mbeats: float(),
          decay_mbeats: float(),
          hold_mbeats: float(),
          release_mbeats: float(),
          interpolation_function: interpolation_function(),
          shift_mbeats: float(),
          anchor: anchor()
        }

  defstruct start_value: 0.0,
            peak_value: 1.0,
            sustain_value: 0.5,
            end_value: 0.0,
            attack_mbeats: 1000.0,
            decay_mbeats: 1000.0,
            hold_mbeats: 1000.0,
            release_mbeats: 1000.0,
            interpolation_function: :linear,
            shift_mbeats: 0.0,
            anchor: :note

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec normalize!(t() | map() | nil, keyword()) :: t()
  def normalize!(lfo_envelope, opts \\ [])

  def normalize!(nil, _opts), do: default()

  def normalize!(%__MODULE__{} = lfo_envelope, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo envelope")

    %__MODULE__{
      start_value: normalize_value!(lfo_envelope.start_value, field_name, :start_value),
      peak_value: normalize_value!(lfo_envelope.peak_value, field_name, :peak_value),
      sustain_value: normalize_value!(lfo_envelope.sustain_value, field_name, :sustain_value),
      end_value: normalize_value!(lfo_envelope.end_value, field_name, :end_value),
      attack_mbeats:
        normalize_non_negative!(lfo_envelope.attack_mbeats, field_name, :attack_mbeats),
      decay_mbeats: normalize_non_negative!(lfo_envelope.decay_mbeats, field_name, :decay_mbeats),
      hold_mbeats: normalize_non_negative!(lfo_envelope.hold_mbeats, field_name, :hold_mbeats),
      release_mbeats:
        normalize_non_negative!(lfo_envelope.release_mbeats, field_name, :release_mbeats),
      interpolation_function:
        normalize_interpolation_function!(lfo_envelope.interpolation_function, field_name),
      shift_mbeats: normalize_value!(lfo_envelope.shift_mbeats, field_name, :shift_mbeats),
      anchor: normalize_anchor!(lfo_envelope.anchor, field_name)
    }
  end

  def normalize!(lfo_envelope, opts) when is_map(lfo_envelope) do
    lfo_envelope
    |> symbolize_map_keys()
    |> then(fn attrs -> struct!(__MODULE__, Map.merge(Map.from_struct(default()), attrs)) end)
    |> normalize!(opts)
  end

  def normalize!(other, opts) do
    field_name = Keyword.get(opts, :field_name, "lfo envelope")
    raise ArgumentError, "#{field_name} must be #{inspect(__MODULE__)}, got: #{inspect(other)}"
  end

  @spec value_at_mbeat(t(), integer(), SampleContext.t(), integer(), integer()) :: float()
  def value_at_mbeat(
        %__MODULE__{} = lfo_envelope,
        at_mbeat,
        %SampleContext{} = _sample_context,
        absolute_chord_start_mbeat,
        note_local_mbeat
      )
      when is_integer(at_mbeat) and is_integer(absolute_chord_start_mbeat) and
             is_integer(note_local_mbeat) do
    timeline_mbeat =
      case lfo_envelope.anchor do
        :sample -> absolute_chord_start_mbeat + at_mbeat
        :chord -> at_mbeat
        :note -> note_local_mbeat
      end

    shifted_mbeat = timeline_mbeat - lfo_envelope.shift_mbeats

    attack_end = lfo_envelope.attack_mbeats
    decay_end = attack_end + lfo_envelope.decay_mbeats
    hold_end = decay_end + lfo_envelope.hold_mbeats
    release_end = hold_end + lfo_envelope.release_mbeats

    cond do
      shifted_mbeat < 0 ->
        lfo_envelope.start_value

      shifted_mbeat <= attack_end and attack_end > 0 ->
        progress = (shifted_mbeat / attack_end) |> clamp_0_1()

        interpolate(
          lfo_envelope.start_value,
          lfo_envelope.peak_value,
          progress,
          lfo_envelope.interpolation_function
        )

      shifted_mbeat <= attack_end ->
        lfo_envelope.peak_value

      shifted_mbeat <= decay_end and lfo_envelope.decay_mbeats > 0 ->
        progress = ((shifted_mbeat - attack_end) / lfo_envelope.decay_mbeats) |> clamp_0_1()

        interpolate(
          lfo_envelope.peak_value,
          lfo_envelope.sustain_value,
          progress,
          lfo_envelope.interpolation_function
        )

      shifted_mbeat <= decay_end ->
        lfo_envelope.sustain_value

      shifted_mbeat <= hold_end ->
        lfo_envelope.sustain_value

      shifted_mbeat <= release_end and lfo_envelope.release_mbeats > 0 ->
        progress = ((shifted_mbeat - hold_end) / lfo_envelope.release_mbeats) |> clamp_0_1()

        interpolate(
          lfo_envelope.sustain_value,
          lfo_envelope.end_value,
          progress,
          lfo_envelope.interpolation_function
        )

      true ->
        lfo_envelope.end_value
    end
  end

  defp interpolate(from, to, progress, interpolation_function) do
    shaped_progress = apply_interpolation(progress, interpolation_function)
    from + (to - from) * shaped_progress
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

  defp normalize_non_negative!(value, _field_name, _value_name)
       when is_integer(value) and value >= 0,
       do: value * 1.0

  defp normalize_non_negative!(value, _field_name, _value_name)
       when is_float(value) and value >= 0,
       do: value

  defp normalize_non_negative!(other, field_name, value_name) do
    raise ArgumentError,
          "#{field_name}.#{value_name} must be >= 0, got: #{inspect(other)}"
  end

  defp normalize_interpolation_function!(function, _field_name)
       when function in [:linear, :ease_in, :ease_out, :ease_in_out],
       do: function

  defp normalize_interpolation_function!(other, field_name) do
    raise ArgumentError,
          "#{field_name}.interpolation_function must be :linear, :ease_in, :ease_out, or :ease_in_out, got: #{inspect(other)}"
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
      {"peak_value", value} -> {:peak_value, value}
      {"sustain_value", value} -> {:sustain_value, value}
      {"end_value", value} -> {:end_value, value}
      {"attack_mbeats", value} -> {:attack_mbeats, value}
      {"decay_mbeats", value} -> {:decay_mbeats, value}
      {"hold_mbeats", value} -> {:hold_mbeats, value}
      {"release_mbeats", value} -> {:release_mbeats, value}
      {"interpolation_function", value} -> {:interpolation_function, value}
      {"shift_mbeats", value} -> {:shift_mbeats, value}
      {"anchor", value} -> {:anchor, value}
      {"time_base", value} -> {:anchor, value}
      {:time_base, value} -> {:anchor, value}
      pair -> pair
    end)
    |> Map.new()
  end
end

defimpl Mensch.NewModulation.Lfo, for: Mensch.NewModulation.LfoEnvelope do
  alias Mensch.NewModulation.LfoEnvelope

  def evaluate(
        %LfoEnvelope{} = lfo_envelope,
        at_mbeat,
        sample_context,
        absolute_chord_start_mbeat,
        note_local_mbeat
      ) do
    lfo_envelope
    |> LfoEnvelope.normalize!(field_name: "lfo envelope")
    |> LfoEnvelope.value_at_mbeat(
      at_mbeat,
      sample_context,
      absolute_chord_start_mbeat,
      note_local_mbeat
    )
  end
end
