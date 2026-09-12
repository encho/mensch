defmodule Mensch.Envelope.ADSR do
  @moduledoc """
  Beat-aware ADSR envelope model.

  External timing inputs can stay in millibeats (`*_mbeats`) and are
  used directly via `from_mbeats/3`. All envelope phase and level
  calculations are done in mbeat domain.
  """

  alias Mensch.SampleContext

  @default_sustain_level 100 / 127

  @type curve :: :linear | :exp | :log | :s_curve

  @type phase :: :attack | :decay | :sustain | :release | :ended

  @type t :: %__MODULE__{
          attack_mbeats: non_neg_integer(),
          decay_mbeats: non_neg_integer(),
          release_mbeats: non_neg_integer(),
          total_mbeats: non_neg_integer(),
          attack_end_mbeat: non_neg_integer(),
          decay_end_mbeat: non_neg_integer(),
          release_start_mbeat: non_neg_integer() | nil,
          attack_curve: curve(),
          decay_curve: curve(),
          release_curve: curve(),
          peak_level: float(),
          sustain_level: float()
        }

  @enforce_keys [
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :total_mbeats,
    :attack_end_mbeat,
    :decay_end_mbeat,
    :release_start_mbeat,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]
  defstruct [
    :attack_mbeats,
    :decay_mbeats,
    :release_mbeats,
    :total_mbeats,
    :attack_end_mbeat,
    :decay_end_mbeat,
    :release_start_mbeat,
    :attack_curve,
    :decay_curve,
    :release_curve,
    :peak_level,
    :sustain_level
  ]

  @spec from_mbeats(non_neg_integer(), SampleContext.t(), map()) :: t()
  def from_mbeats(total_mbeats, %SampleContext{} = sample_context, params)
      when is_integer(total_mbeats) and total_mbeats >= 0 and is_map(params) do
    attack_mbeats =
      sample_context
      |> SampleContext.mbeats_to_units(Map.get(params, :attack_mbeats, 0))

    decay_mbeats =
      sample_context
      |> SampleContext.mbeats_to_units(Map.get(params, :decay_mbeats, 0))

    release_mbeats =
      sample_context
      |> SampleContext.mbeats_to_units(Map.get(params, :release_mbeats, 0))

    new(total_mbeats, attack_mbeats, decay_mbeats, release_mbeats,
      attack_curve: Map.get(params, :attack_curve, :linear),
      decay_curve: Map.get(params, :decay_curve, :linear),
      release_curve: Map.get(params, :release_curve, :linear),
      peak_level: Map.get(params, :peak_level, 1.0),
      sustain_level: Map.get(params, :sustain_level, @default_sustain_level)
    )
  end

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          t()
  def new(total_mbeats, attack_mbeats, decay_mbeats, release_mbeats, opts \\ [])
      when is_integer(total_mbeats) and total_mbeats >= 0 and is_integer(attack_mbeats) and
             attack_mbeats >= 0 and is_integer(decay_mbeats) and decay_mbeats >= 0 and
             is_integer(release_mbeats) and release_mbeats >= 0 do
    peak_level = opts |> Keyword.get(:peak_level, 1.0) |> clamp_level()
    sustain_level = opts |> Keyword.get(:sustain_level, @default_sustain_level) |> clamp_level()
    attack_curve = opts |> Keyword.get(:attack_curve, :linear) |> normalize_curve()
    decay_curve = opts |> Keyword.get(:decay_curve, :linear) |> normalize_curve()
    release_curve = opts |> Keyword.get(:release_curve, :linear) |> normalize_curve()

    attack_end_mbeat = min(attack_mbeats, total_mbeats)
    decay_end_mbeat = min(attack_end_mbeat + decay_mbeats, total_mbeats)

    release_start_mbeat =
      if release_mbeats == 0 do
        nil
      else
        max(total_mbeats - release_mbeats, 0)
      end

    %__MODULE__{
      attack_mbeats: attack_mbeats,
      decay_mbeats: decay_mbeats,
      release_mbeats: release_mbeats,
      total_mbeats: total_mbeats,
      attack_end_mbeat: attack_end_mbeat,
      decay_end_mbeat: decay_end_mbeat,
      release_start_mbeat: release_start_mbeat,
      attack_curve: attack_curve,
      decay_curve: decay_curve,
      release_curve: release_curve,
      peak_level: peak_level,
      sustain_level: sustain_level
    }
  end

  @spec phase_at_mbeat(t(), non_neg_integer()) :: phase()
  def phase_at_mbeat(%__MODULE__{} = adsr, elapsed_mbeats)
      when is_integer(elapsed_mbeats) and elapsed_mbeats >= 0 do
    cond do
      elapsed_mbeats > adsr.total_mbeats ->
        :ended

      elapsed_mbeats < adsr.attack_end_mbeat ->
        :attack

      elapsed_mbeats < adsr.decay_end_mbeat ->
        :decay

      not is_nil(adsr.release_start_mbeat) and elapsed_mbeats >= adsr.release_start_mbeat ->
        :release

      true ->
        :sustain
    end
  end

  @spec level_at_mbeat(t(), non_neg_integer()) :: float()
  def level_at_mbeat(%__MODULE__{} = adsr, elapsed_mbeats)
      when is_integer(elapsed_mbeats) and elapsed_mbeats >= 0 do
    cond do
      elapsed_mbeats > adsr.total_mbeats ->
        0.0

      elapsed_mbeats < adsr.attack_end_mbeat ->
        ratio =
          safe_ratio(elapsed_mbeats, adsr.attack_end_mbeat) |> shape_ratio(adsr.attack_curve)

        lerp(0.0, adsr.peak_level, ratio)

      elapsed_mbeats < adsr.decay_end_mbeat ->
        ratio =
          safe_ratio(
            elapsed_mbeats - adsr.attack_end_mbeat,
            adsr.decay_end_mbeat - adsr.attack_end_mbeat
          )
          |> shape_ratio(adsr.decay_curve)

        lerp(adsr.peak_level, adsr.sustain_level, ratio)

      not is_nil(adsr.release_start_mbeat) and elapsed_mbeats >= adsr.release_start_mbeat ->
        ratio =
          safe_ratio(
            elapsed_mbeats - adsr.release_start_mbeat,
            adsr.total_mbeats - adsr.release_start_mbeat
          )
          |> shape_ratio(adsr.release_curve)

        lerp(adsr.sustain_level, 0.0, ratio)

      true ->
        adsr.sustain_level
    end
  end

  @spec in_sustain_mbeat?(t(), non_neg_integer()) :: boolean()
  def in_sustain_mbeat?(%__MODULE__{} = adsr, elapsed_mbeats)
      when is_integer(elapsed_mbeats) and elapsed_mbeats >= 0 do
    elapsed_mbeats < adsr.total_mbeats and elapsed_mbeats >= adsr.decay_end_mbeat and
      (is_nil(adsr.release_start_mbeat) or elapsed_mbeats < adsr.release_start_mbeat)
  end

  defp clamp_level(value) when is_float(value), do: value |> max(0.0) |> min(1.0)
  defp clamp_level(value) when is_integer(value), do: value |> Kernel./(1) |> clamp_level()
  defp clamp_level(_value), do: @default_sustain_level

  defp normalize_curve(curve) when curve in [:linear, :exp, :log, :s_curve], do: curve
  defp normalize_curve(_curve), do: :linear

  defp shape_ratio(ratio, :linear), do: ratio
  defp shape_ratio(ratio, :exp), do: ratio * ratio
  defp shape_ratio(ratio, :log), do: 1.0 - (1.0 - ratio) * (1.0 - ratio)
  defp shape_ratio(ratio, :s_curve), do: ratio * ratio * (3.0 - 2.0 * ratio)

  defp lerp(from, to, ratio), do: from + (to - from) * ratio

  defp safe_ratio(_numerator, denominator) when denominator <= 0, do: 1.0
  defp safe_ratio(numerator, denominator), do: (numerator / denominator) |> max(0.0) |> min(1.0)
end
