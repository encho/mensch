defmodule Mensch.Midi.ChannelPoolTest do
  use ExUnit.Case, async: true

  alias Mensch.Midi.ChannelPool

  setup do
    name = :"channel_pool_#{System.unique_integer([:positive])}"
    start_supervised!({ChannelPool, name: name, channels: [1, 2, 3]})
    {:ok, pool: name}
  end

  test "checkout hands out free channels and checkin returns them", %{pool: pool} do
    assert Enum.sort(ChannelPool.checkout(2, pool)) == [1, 2]
    assert ChannelPool.checkout(1, pool) == [3]
    # Pool is exhausted now.
    assert ChannelPool.checkout(1, pool) == []

    ChannelPool.checkin(2, pool)
    _ = :sys.get_state(GenServer.whereis(pool))
    assert ChannelPool.checkout(1, pool) == [2]
  end

  test "reclaims all channels owned by a crashed caller", %{pool: pool} do
    test_pid = self()

    {owner, ref} =
      spawn_monitor(fn ->
        channels = ChannelPool.checkout(3, pool)
        send(test_pid, {:checked_out, channels})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:checked_out, [_, _, _] = channels}
    assert ChannelPool.checkout(1, pool) == []

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}

    # Give the pool a moment to process its own :DOWN message.
    _ = :sys.get_state(GenServer.whereis(pool))
    assert Enum.sort(ChannelPool.checkout(3, pool)) == Enum.sort(channels)
  end
end
