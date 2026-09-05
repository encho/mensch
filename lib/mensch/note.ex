defmodule Mensch.Note do
  @moduledoc """
  Represents a single sounding MIDI note on a dedicated MPE member
  channel. Sends note-on when started, and always sends note-off when
  stopped (whether stopped cooperatively or shut down by its parent
  `Mensch.Chord`), so a note can never get stuck sounding on the
  hardware.
  """

  use GenServer

  defstruct [:number, :channel, :velocity]

  # Client API

  @doc """
  Starts a note. `opts` must include `:number` (MIDI note number 0-127),
  `:channel` (MPE member channel 0-15) and optionally `:velocity`
  (defaults to 100).
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the note, sending note-off before terminating."
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      number: Keyword.fetch!(opts, :number),
      channel: Keyword.fetch!(opts, :channel),
      velocity: Keyword.get(opts, :velocity, 100)
    }

    Mensch.Midi.Connection.send_message(<<0x90 + state.channel, state.number, state.velocity>>)

    {:ok, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    Mensch.Midi.Connection.send_message(<<0x80 + state.channel, state.number, 0>>)
    :ok
  end
end
