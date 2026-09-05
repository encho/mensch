defmodule Mensch.ChordSupervisor do
  @moduledoc """
  DynamicSupervisor for `Mensch.ChordPlayer` processes: one child per
  currently-playing chord, started when PLAY is clicked and terminated
  when STOP is clicked.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts a `Mensch.ChordPlayer` child. See `Mensch.ChordPlayer.start_link/1` for `opts`."
  def start_chord(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Mensch.ChordPlayer, opts})
  end

  @doc "Stops a running chord."
  def stop_chord(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
