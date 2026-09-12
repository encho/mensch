defmodule Mensch.SampleContext do
  @moduledoc """
  Global sample timing context.

  Internally, timing resolution is millibeats (mbeats):

    * one beat = 1000 mbeats
    * frame stepping is `frame_mbeats`

  `frame_mbeats` must divide 1000 so every beat boundary always lands on
  a frame boundary.

  For compatibility with existing callers and MIDI export code, this module
  still exposes tick-named helpers, where one internal "tick" equals one
  mbeat.
  """

  alias Mensch.BeatPosition

  @type t :: %__MODULE__{
          bpm: pos_integer(),
          time_signature: {pos_integer(), pos_integer()},
          frame_mbeats: pos_integer()
        }

  @enforce_keys [:bpm, :time_signature, :frame_mbeats]
  defstruct [:bpm, :time_signature, :frame_mbeats]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    __MODULE__
    |> struct(attrs)
    |> validate()
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise ArgumentError, "invalid sample context: #{inspect(reason)}"
    end
  end

  @doc "Validates an already-built `SampleContext` struct."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = ctx) do
    cond do
      not is_integer(ctx.bpm) or ctx.bpm <= 0 ->
        {:error, {:invalid_bpm, ctx.bpm}}

      not valid_time_signature?(ctx.time_signature) ->
        {:error, {:invalid_time_signature, ctx.time_signature}}

      not is_integer(ctx.frame_mbeats) or ctx.frame_mbeats <= 0 ->
        {:error, {:invalid_frame_mbeats, ctx.frame_mbeats}}

      rem(1000, ctx.frame_mbeats) != 0 ->
        {:error, {:frame_mbeats_must_divide_beat, ctx.frame_mbeats}}

      true ->
        {:ok, ctx}
    end
  end

  @doc "Validates an already-built `SampleContext` struct and raises on error."
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = ctx) do
    case validate(ctx) do
      {:ok, valid_ctx} -> valid_ctx
      {:error, reason} -> raise ArgumentError, "invalid sample context: #{inspect(reason)}"
    end
  end

  @doc "Beats per bar derived from the time signature numerator."
  @spec beats_per_bar(t()) :: pos_integer()
  def beats_per_bar(%__MODULE__{time_signature: {beats, _denominator}}), do: beats

  @doc "Millibeats represented by one internal tick (compatibility alias)."
  @spec mbeats_per_tick(t()) :: pos_integer()
  def mbeats_per_tick(%__MODULE__{}), do: 1

  @doc "Internal ticks per beat (compatibility alias), always 1000."
  @spec ticks_per_beat(t()) :: pos_integer()
  def ticks_per_beat(%__MODULE__{}), do: 1000

  @doc "Global render frame size in millibeats."
  @spec frame_mbeats(t()) :: pos_integer()
  def frame_mbeats(%__MODULE__{frame_mbeats: frame_mbeats}), do: frame_mbeats

  @doc "Converts millibeats to nearest tick."
  @spec mbeats_to_ticks(t(), non_neg_integer()) :: non_neg_integer()
  def mbeats_to_ticks(%__MODULE__{} = sample_context, mbeats)
      when is_integer(mbeats) and mbeats >= 0 do
    _ = sample_context
    mbeats
  end

  @doc "Global render frame size in ticks (at least 1)."
  @spec frame_ticks(t()) :: pos_integer()
  def frame_ticks(%__MODULE__{} = sample_context) do
    sample_context
    |> frame_mbeats()
    |> then(&mbeats_to_ticks(sample_context, &1))
    |> max(1)
  end

  @doc "Ticks per bar."
  @spec ticks_per_bar(t()) :: pos_integer()
  def ticks_per_bar(%__MODULE__{} = sample_context) do
    beats_per_bar(sample_context) * ticks_per_beat(sample_context)
  end

  @doc "Milliseconds per beat."
  @spec ms_per_beat(t()) :: float()
  def ms_per_beat(%__MODULE__{bpm: bpm}), do: 60_000 / bpm

  @doc "Milliseconds per tick."
  @spec ms_per_tick(t()) :: float()
  def ms_per_tick(%__MODULE__{} = sample_context) do
    ms_per_beat(sample_context) / ticks_per_beat(sample_context)
  end

  @doc "Milliseconds per millibeat."
  @spec ms_per_mbeat(t()) :: float()
  def ms_per_mbeat(%__MODULE__{} = sample_context), do: ms_per_tick(sample_context)

  @doc "Converts millibeats to milliseconds from sample start."
  @spec mbeats_to_ms(t(), non_neg_integer()) :: non_neg_integer()
  def mbeats_to_ms(%__MODULE__{} = sample_context, mbeats)
      when is_integer(mbeats) and mbeats >= 0 do
    ticks_to_ms(sample_context, mbeats)
  end

  @doc "Converts milliseconds from sample start to nearest millibeat."
  @spec ms_to_mbeats(t(), non_neg_integer()) :: non_neg_integer()
  def ms_to_mbeats(%__MODULE__{} = sample_context, ms) when is_integer(ms) and ms >= 0 do
    ms_to_ticks(sample_context, ms)
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

  @doc "Converts a beat position (`bar`/`beat`/`mbeat`) to absolute tick."
  @spec position_to_tick(t(), BeatPosition.t()) :: non_neg_integer()
  def position_to_tick(%__MODULE__{} = sample_context, %BeatPosition{} = beat_position) do
    beat_position.bar * ticks_per_bar(sample_context) +
      beat_position.beat * ticks_per_beat(sample_context) +
      mbeats_to_ticks(sample_context, beat_position.mbeat)
  end

  @doc "Converts an absolute tick to zero-based `bar`/`beat`/`mbeat`."
  @spec tick_to_position(t(), non_neg_integer()) :: BeatPosition.t()
  def tick_to_position(%__MODULE__{} = sample_context, absolute_tick)
      when is_integer(absolute_tick) and absolute_tick >= 0 do
    ticks_per_bar = ticks_per_bar(sample_context)
    ticks_per_beat = ticks_per_beat(sample_context)

    bar = div(absolute_tick, ticks_per_bar)
    in_bar = rem(absolute_tick, ticks_per_bar)
    beat = div(in_bar, ticks_per_beat)
    tick_in_beat = rem(in_bar, ticks_per_beat)
    mbeat = round(tick_in_beat * 1000 / ticks_per_beat)

    BeatPosition.new(bar, beat, min(mbeat, 999))
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
