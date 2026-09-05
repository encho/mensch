defmodule Mensch.Midi.ChannelPool do
  @moduledoc """
  Tracks which MPE member channels are currently in use.

  With chords now able to overlap in time (one still releasing while
  the next has already started - see `Mensch.Sequencer`), channel
  assignment can no longer be a stateless "take the first N" like
  before: two overlapping chords must never be handed the same
  channel. Callers (`Mensch.ChordPlayer`) `checkout/1` up to the
  number of channels they need for a chord and `checkin/1` each one
  back as its note naturally finishes. The pool also monitors every
  checkout's caller so a crash can never leak a channel forever.

  `checkout/1` never blocks waiting for free channels - it returns
  however many are currently available (possibly fewer than asked
  for, possibly zero). Callers should degrade gracefully (e.g. sound
  fewer notes) rather than delay, since it's more important that a
  chord starts exactly on time than that every one of its notes
  sounds.
  """

  use GenServer

  alias Mensch.Midi.Connection

  defstruct available: [], owners: %{}, monitors: %{}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Checks out up to `count` free channels for the calling process,
  returning the list actually granted (`0..count` channels). The
  caller is monitored so its channels are automatically reclaimed if
  it crashes.
  """
  def checkout(count, pool \\ __MODULE__) when is_integer(count) and count >= 0 do
    GenServer.call(pool, {:checkout, count})
  end

  @doc "Returns a channel to the pool, available for reuse."
  def checkin(channel, pool \\ __MODULE__) do
    GenServer.cast(pool, {:checkin, channel})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    channels = Keyword.get(opts, :channels, Connection.member_channels())
    {:ok, %__MODULE__{available: channels}}
  end

  @impl true
  def handle_call({:checkout, count}, {from_pid, _tag}, state) do
    {taken, remaining} = Enum.split(state.available, count)

    state =
      if taken == [] do
        state
      else
        owners = Enum.reduce(taken, state.owners, &Map.put(&2, &1, from_pid))
        %{state | available: remaining, owners: owners} |> ensure_monitored(from_pid)
      end

    {:reply, taken, state}
  end

  @impl true
  def handle_cast({:checkin, channel}, state) do
    {:noreply, reclaim(state, channel)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    channels = for {channel, owner} <- state.owners, owner == pid, do: channel
    state = Enum.reduce(channels, state, &reclaim(&2, &1))
    {:noreply, %{state | monitors: Map.delete(state.monitors, ref)}}
  end

  defp ensure_monitored(state, pid) do
    if Enum.any?(state.monitors, fn {_ref, monitored_pid} -> monitored_pid == pid end) do
      state
    else
      ref = Process.monitor(pid)
      %{state | monitors: Map.put(state.monitors, ref, pid)}
    end
  end

  defp reclaim(state, channel) do
    case Map.pop(state.owners, channel) do
      {nil, _owners} -> state
      {_owner, owners} -> %{state | owners: owners, available: [channel | state.available]}
    end
  end
end
