defmodule Mensch.SampleContext do
  @moduledoc """
  Global sample timing context.

  PPQ means pulses per quarter note (ticks per beat). This module keeps
  PPQ internal, while exposing helpers to convert to/from human-friendly
  beat positions and wall-clock timestamps.
  """

  alias Mensch.BeatPosition

  @type t :: %__MODULE__{
          bpm: pos_integer(),
          time_signature: {pos_integer(), pos_integer()},
          ppq: pos_integer()
        }

  @enforce_keys [:bpm, :time_signature, :ppq]
  defstruct [:bpm, :time_signature, :ppq]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    ctx = struct(__MODULE__, attrs)

    cond do
      not is_integer(ctx.bpm) or ctx.bpm <= 0 ->
        {:error, {:invalid_bpm, ctx.bpm}}

      not valid_time_signature?(ctx.time_signature) ->
        {:error, {:invalid_time_signature, ctx.time_signature}}

      not is_integer(ctx.ppq) or ctx.ppq <= 0 ->
        {:error, {:invalid_ppq, ctx.ppq}}

      true ->
        {:ok, ctx}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise ArgumentError, "invalid sample context: #{inspect(reason)}"
    end
  end

  @doc "Beats per bar derived from the time signature numerator."
  @spec beats_per_bar(t()) :: pos_integer()
  def beats_per_bar(%__MODULE__{time_signature: {beats, _denominator}}), do: beats

  @doc "Ticks per beat (`ppq`)."
  @spec ticks_per_beat(t()) :: pos_integer()
  def ticks_per_beat(%__MODULE__{ppq: ppq}), do: ppq

  @doc "Ticks per bar."
  @spec ticks_per_bar(t()) :: pos_integer()
  def ticks_per_bar(%__MODULE__{} = sample_context) do
    beats_per_bar(sample_context) * ticks_per_beat(sample_context)
  end

  @doc "Milliseconds per beat."
  @spec ms_per_beat(t()) :: float()
  def ms_per_beat(%__MODULE__{bpm: bpm}), do: 60_000 / bpm

  @doc "Milliseconds per PPQ tick."
  @spec ms_per_tick(t()) :: float()
  def ms_per_tick(%__MODULE__{} = sample_context) do
    ms_per_beat(sample_context) / ticks_per_beat(sample_context)
  end

  @doc "Converts absolute ticks to milliseconds from sample start."
  @spec ticks_to_ms(t(), non_neg_integer()) :: non_neg_integer()
  def ticks_to_ms(%__MODULE__{} = sample_context, ticks) when is_integer(ticks) and ticks >= 0 do
    round(ticks * ms_per_tick(sample_context))
  end

  @doc "Converts milliseconds from sample start to nearest absolute tick."
  @spec ms_to_ticks(t(), non_neg_integer()) :: non_neg_integer()
  def ms_to_ticks(%__MODULE__{} = sample_context, ms) when is_integer(ms) and ms >= 0 do
    round(ms / ms_per_tick(sample_context))
  end

  @doc "Converts a beat position (`bar`/`beat`/`tick`) to absolute tick."
  @spec position_to_tick(t(), BeatPosition.t()) :: non_neg_integer()
  def position_to_tick(%__MODULE__{} = sample_context, %BeatPosition{} = beat_position) do
    beat_position.bar * ticks_per_bar(sample_context) +
      beat_position.beat * ticks_per_beat(sample_context) +
      beat_position.tick
  end

  @doc "Converts an absolute tick to zero-based `bar`/`beat`/`tick`."
  @spec tick_to_position(t(), non_neg_integer()) :: BeatPosition.t()
  def tick_to_position(%__MODULE__{} = sample_context, absolute_tick)
      when is_integer(absolute_tick) and absolute_tick >= 0 do
    ticks_per_bar = ticks_per_bar(sample_context)
    ticks_per_beat = ticks_per_beat(sample_context)

    bar = div(absolute_tick, ticks_per_bar)
    in_bar = rem(absolute_tick, ticks_per_bar)
    beat = div(in_bar, ticks_per_beat)
    tick = rem(in_bar, ticks_per_beat)

    BeatPosition.new(bar, beat, tick)
  end

  @doc "Converts milliseconds to `MM:SS.mmm` format."
  @spec format_timestamp(non_neg_integer()) :: String.t()
  def format_timestamp(ms) when is_integer(ms) and ms >= 0 do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    millis = rem(ms, 1000)
    :io_lib.format("~2..0B:~2..0B.~3..0B", [minutes, seconds, millis]) |> IO.iodata_to_binary()
  end

  defp valid_time_signature?({num, den}) do
    is_integer(num) and num > 0 and is_integer(den) and den > 0
  end

  defp valid_time_signature?(_), do: false
end
