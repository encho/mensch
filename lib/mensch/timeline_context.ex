defmodule Mensch.TimelineContext do
  @moduledoc """
  Placement of a chord event on a sample timeline.

  `start_beat` and `duration_mbeats` are external, human-readable timing
  inputs. Internal consumers derive ticks via `duration_ticks/2`.
  """

  alias Mensch.BeatPosition
  alias Mensch.SampleContext

  @type t :: %__MODULE__{start_beat: BeatPosition.t(), duration_mbeats: non_neg_integer()}

  @enforce_keys [:start_beat, :duration_mbeats]
  defstruct [:start_beat, :duration_mbeats]

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    ctx = struct(__MODULE__, attrs)

    cond do
      not match?(%BeatPosition{}, ctx.start_beat) ->
        {:error, {:invalid_start_beat, ctx.start_beat}}

      not is_integer(ctx.duration_mbeats) or ctx.duration_mbeats < 0 ->
        {:error, {:invalid_duration_mbeats, ctx.duration_mbeats}}

      true ->
        {:ok, ctx}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise ArgumentError, "invalid timeline context: #{inspect(reason)}"
    end
  end

  @doc "Absolute start tick for this timeline context."
  @spec start_tick(t(), SampleContext.t()) :: non_neg_integer()
  def start_tick(%__MODULE__{} = timeline_context, %SampleContext{} = sample_context) do
    SampleContext.position_to_tick(sample_context, timeline_context.start_beat)
  end

  @doc "Absolute end tick for this timeline context."
  @spec end_tick(t(), SampleContext.t()) :: non_neg_integer()
  def end_tick(%__MODULE__{} = timeline_context, %SampleContext{} = sample_context) do
    start_tick(timeline_context, sample_context) +
      duration_ticks(timeline_context, sample_context)
  end

  @doc "Entry duration converted to ticks for internal scheduling math."
  @spec duration_ticks(t(), SampleContext.t()) :: non_neg_integer()
  def duration_ticks(%__MODULE__{} = timeline_context, %SampleContext{} = sample_context) do
    SampleContext.mbeats_to_ticks(sample_context, timeline_context.duration_mbeats)
  end
end
