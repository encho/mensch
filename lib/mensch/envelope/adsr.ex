defmodule Mensch.Envelope.ADSR do
  @moduledoc """
  Beat-aware ADSR envelope model.

  External timing inputs can stay in millibeats (`*_mbeats`) and are
  converted to ticks once via `from_mbeats/3`. All envelope phase and
  level calculations are then done in tick domain.
  """

  alias Mensch.SampleContext

  @default_sustain_level 100 / 127

  @type phase :: :attack | :decay | :sustain | :release

  @type t :: %__MODULE__{
          attack_ticks: non_neg_integer(),
          decay_ticks: non_neg_integer(),
          release_ticks: non_neg_integer(),
          total_ticks: non_neg_integer(),
          attack_end_tick: non_neg_integer(),
          decay_end_tick: non_neg_integer(),
          release_start_tick: non_neg_integer() | nil,
          peak_level: float(),
          sustain_level: float()
        }

  @enforce_keys [
    :attack_ticks,
    :decay_ticks,
    :release_ticks,
    :total_ticks,
    :attack_end_tick,
    :decay_end_tick,
    :release_start_tick,
    :peak_level,
    :sustain_level
  ]
  defstruct [
    :attack_ticks,
    :decay_ticks,
    :release_ticks,
    :total_ticks,
    :attack_end_tick,
    :decay_end_tick,
    :release_start_tick,
    :peak_level,
    :sustain_level
  ]

  @spec from_mbeats(non_neg_integer(), SampleContext.t(), map()) :: t()
  def from_mbeats(total_ticks, %SampleContext{} = sample_context, params)
      when is_integer(total_ticks) and total_ticks >= 0 and is_map(params) do
    attack_ticks =
      sample_context
      |> SampleContext.mbeats_to_ticks(Map.get(params, :attack_mbeats, 0))

    decay_ticks =
      sample_context
      |> SampleContext.mbeats_to_ticks(Map.get(params, :decay_mbeats, 0))

    release_ticks =
      sample_context
      |> SampleContext.mbeats_to_ticks(Map.get(params, :release_mbeats, 0))

    new(total_ticks, attack_ticks, decay_ticks, release_ticks,
      peak_level: Map.get(params, :peak_level, 1.0),
      sustain_level: Map.get(params, :sustain_level, @default_sustain_level)
    )
  end

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          t()
  def new(total_ticks, attack_ticks, decay_ticks, release_ticks, opts \\ [])
      when is_integer(total_ticks) and total_ticks >= 0 and is_integer(attack_ticks) and
             attack_ticks >= 0 and is_integer(decay_ticks) and decay_ticks >= 0 and
             is_integer(release_ticks) and release_ticks >= 0 do
    peak_level = opts |> Keyword.get(:peak_level, 1.0) |> clamp_level()
    sustain_level = opts |> Keyword.get(:sustain_level, @default_sustain_level) |> clamp_level()

    attack_end_tick = min(attack_ticks, total_ticks)
    decay_end_tick = min(attack_end_tick + decay_ticks, total_ticks)

    release_start_tick =
      if release_ticks == 0 do
        nil
      else
        max(total_ticks - release_ticks, 0)
      end

    %__MODULE__{
      attack_ticks: attack_ticks,
      decay_ticks: decay_ticks,
      release_ticks: release_ticks,
      total_ticks: total_ticks,
      attack_end_tick: attack_end_tick,
      decay_end_tick: decay_end_tick,
      release_start_tick: release_start_tick,
      peak_level: peak_level,
      sustain_level: sustain_level
    }
  end

  @spec phase_at_tick(t(), non_neg_integer()) :: phase()
  def phase_at_tick(%__MODULE__{} = adsr, elapsed_ticks)
      when is_integer(elapsed_ticks) and elapsed_ticks >= 0 do
    cond do
      elapsed_ticks < adsr.attack_end_tick -> :attack
      elapsed_ticks < adsr.decay_end_tick -> :decay
      not is_nil(adsr.release_start_tick) and elapsed_ticks >= adsr.release_start_tick -> :release
      true -> :sustain
    end
  end

  @spec level_at_tick(t(), non_neg_integer()) :: float()
  def level_at_tick(%__MODULE__{} = adsr, elapsed_ticks)
      when is_integer(elapsed_ticks) and elapsed_ticks >= 0 do
    cond do
      elapsed_ticks < adsr.attack_end_tick ->
        ratio = safe_ratio(elapsed_ticks, adsr.attack_end_tick)
        lerp(0.0, adsr.peak_level, ratio)

      elapsed_ticks < adsr.decay_end_tick ->
        ratio =
          safe_ratio(
            elapsed_ticks - adsr.attack_end_tick,
            adsr.decay_end_tick - adsr.attack_end_tick
          )

        lerp(adsr.peak_level, adsr.sustain_level, ratio)

      not is_nil(adsr.release_start_tick) and elapsed_ticks >= adsr.release_start_tick ->
        ratio =
          safe_ratio(
            elapsed_ticks - adsr.release_start_tick,
            adsr.total_ticks - adsr.release_start_tick
          )

        lerp(adsr.sustain_level, 0.0, ratio)

      true ->
        adsr.sustain_level
    end
  end

  @spec in_sustain_tick?(t(), non_neg_integer()) :: boolean()
  def in_sustain_tick?(%__MODULE__{} = adsr, elapsed_ticks)
      when is_integer(elapsed_ticks) and elapsed_ticks >= 0 do
    elapsed_ticks >= adsr.decay_end_tick and
      (is_nil(adsr.release_start_tick) or elapsed_ticks < adsr.release_start_tick)
  end

  defp clamp_level(value) when is_float(value), do: value |> max(0.0) |> min(1.0)
  defp clamp_level(value) when is_integer(value), do: value |> Kernel./(1) |> clamp_level()
  defp clamp_level(_value), do: @default_sustain_level

  defp lerp(from, to, ratio), do: from + (to - from) * ratio

  defp safe_ratio(_numerator, denominator) when denominator <= 0, do: 1.0
  defp safe_ratio(numerator, denominator), do: (numerator / denominator) |> max(0.0) |> min(1.0)
end
