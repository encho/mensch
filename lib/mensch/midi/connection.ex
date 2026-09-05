defmodule Mensch.Midi.Connection do
  @moduledoc """
  Owns the real-time MIDI output connection to the Osmose (or any
  configured MIDI output device).

  The device is looked up by name pattern via `Midiex.ports/2`. Osmose
  exposes two MIDI ports; only "Osmose Port 2" (the "Haken" port) is
  wired to its EaganMatrix sound engine ("Osmose Port 1" does not
  produce audio), so the default pattern matches that one
  specifically. This can be overridden with:

      config :mensch, :midi_output_port_pattern, ~r/some other name/i

  Each note is sent on its own MIDI channel (true MPE) so it can carry
  independent per-note modulation (Channel Pressure, Pitch Bend). Per
  Osmose's own MIDI implementation notes, individual notes must be
  sent on channels #2-#14 (channel #1 is reserved/Master, #15-#16 are
  reserved for Haken Editor communication), and velocity ("MPE
  Strike") is ignored entirely by the EaganMatrix - a continuous
  stream of Channel Pressure messages is required to shape (and even
  produce) each note's sound, which `Mensch.NotePlayer` sends on a timer.
  The member channel range can be overridden with:

      config :mensch, :midi_member_channels, [1, 2, 3]

  If no matching port is found (e.g. the hardware isn't plugged in,
  or in test/CI environments), the connection stays `:disconnected`
  instead of crashing the application. Call `reconnect/0` once the
  device is available.
  """

  use GenServer

  require Logger

  @default_member_channels Enum.to_list(1..13)

  defstruct [:out_conn, :port_name, :port_pattern]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The MPE member channels (index 1-15) available for per-note allocation."
  def member_channels do
    Application.get_env(:mensch, :midi_member_channels, @default_member_channels)
  end

  @doc "Sends a raw MIDI message (binary) to the connected output device."
  @spec send_message(binary()) :: :ok | {:error, :disconnected}
  def send_message(bytes) when is_binary(bytes) do
    GenServer.call(__MODULE__, {:send, bytes})
  end

  @doc "Returns `{:connected, port_name}` or `:disconnected`."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Retries locating and opening the configured MIDI output port."
  def reconnect do
    GenServer.call(__MODULE__, :reconnect)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    pattern = Keyword.get(opts, :port_pattern, default_port_pattern())
    {:ok, connect(%__MODULE__{port_pattern: pattern})}
  end

  @impl true
  def handle_call({:send, _bytes}, _from, %__MODULE__{out_conn: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call({:send, bytes}, _from, %__MODULE__{out_conn: out_conn} = state) do
    Midiex.send_msg(out_conn, bytes)
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, connection_status(state), state}
  end

  def handle_call(:reconnect, _from, state) do
    new_state = connect(state)
    {:reply, connection_status(new_state), new_state}
  end

  defp connection_status(%__MODULE__{out_conn: nil}), do: :disconnected
  defp connection_status(%__MODULE__{port_name: port_name}), do: {:connected, port_name}

  defp connect(state) do
    case Midiex.ports(state.port_pattern, :output) do
      [port | _] ->
        out_conn = Midiex.open(port)
        Logger.info("Mensch.Midi.Connection: connected to #{port.name}")
        %{state | out_conn: out_conn, port_name: port.name}

      [] ->
        Logger.warning(
          "Mensch.Midi.Connection: no MIDI output port matching #{inspect(state.port_pattern)} found"
        )

        %{state | out_conn: nil, port_name: nil}
    end
  end

  defp default_port_pattern do
    Application.get_env(:mensch, :midi_output_port_pattern, ~r/osmose.*2/i)
  end
end
