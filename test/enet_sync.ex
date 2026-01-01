defmodule EnetCore.Sync do
  @moduledoc """
  Synchronous ENet operations for testing.
  Converted from enet_sync.erl.
  """

  alias EnetCore
  alias EnetCore.Peer

  def start_host(connect_fun, options) do
    EnetCore.start_host(0, connect_fun, options)
  end

  def connect_from_full_local_host(local_host, remote_port, channel_count) do
    connect(local_host, remote_port, channel_count)
  end

  def connect_to_full_remote_host(local_host, remote_port, channel_count) do
    connect(local_host, remote_port, channel_count)
  end

  def connect_to_self(local_host, remote_port, channel_count) do
    connect(local_host, remote_port, channel_count)
  end

  def connect(local_host, remote_port, channel_count) do
    case EnetCore.connect_peer(local_host, "127.0.0.1", remote_port, channel_count) do
      {:error, :reached_peer_limit} ->
        {:error, :reached_peer_limit}

      {:ok, l_peer} ->
        receive do
          %{peer: lp, channels: lcs, connect_id: cid} ->
            receive do
              %{peer: rp, channels: rcs, connect_id: ^cid} ->
                {lp, lcs, rp, rcs}
            after
              1000 -> {:error, :remote_timeout}
            end
        after
          2000 ->
            pool = Peer.get_pool(l_peer)
            name = Peer.get_name(l_peer)
            Process.exit(l_peer, :normal)
            wait_until_worker_has_left_pool(pool, name)
            {:error, :local_timeout}
        end
    end
  end

  def disconnect(l_pid, r_pid) do
    l_pool = Peer.get_pool(l_pid)
    r_pool = Peer.get_pool(r_pid)
    l_name = Peer.get_name(l_pid)
    r_name = Peer.get_name(r_pid)

    :ok = EnetCore.disconnect_peer(l_pid)

    receive do
      {:enet, :disconnected, :local, ^l_pid, connect_id} ->
        receive do
          {:enet, :disconnected, :remote, ^r_pid, ^connect_id} ->
            wait_until_worker_has_left_pool(l_pool, l_name)
            wait_until_worker_has_left_pool(r_pool, r_name)
        after
          5000 -> {:error, :remote_timeout}
        end
    after
      5000 -> {:error, :local_timeout}
    end
  end

  def stop_host(port) do
    remote_connected_peers =
      :gproc.select([
        {{{:p, :l, :remote_host_port}, :"$1", port}, [], [:"$1"]}
      ])

    peer_monitors =
      Enum.map(remote_connected_peers, fn peer ->
        pool = Peer.get_pool(peer)
        name = Peer.get_name(peer)
        {peer, pool, name}
      end)

    [pid] = :gproc.select([{{{:p, :l, :port}, :"$1", port}, [], [:"$1"]}])
    ref = Process.monitor(pid)

    :ok = EnetCore.stop_host(port)

    receive do
      {:DOWN, ^ref, :process, ^pid, :shutdown} ->
        Enum.each(peer_monitors, fn
          {peer, pool, _name} when pool == port ->
            Process.exit(peer, :normal)

          {peer, pool, name} ->
            Process.exit(peer, :normal)
            wait_until_worker_has_left_pool(pool, name)
        end)
    after
      1000 -> {:error, :timeout}
    end
  end

  def send_unsequenced(channel, data) do
    EnetCore.send_unsequenced(channel, data)

    receive do
      {:enet, _id, ^data} -> :ok
    after
      1000 -> {:error, :data_not_received}
    end
  end

  def send_unreliable(channel, data) do
    EnetCore.send_unreliable(channel, data)

    receive do
      {:enet, _id, ^data} -> :ok
    after
      1000 -> {:error, :data_not_received}
    end
  end

  def send_reliable(channel, data) do
    EnetCore.send_reliable(channel, data)

    receive do
      {:enet, _id, ^data} -> :ok
    after
      1000 -> {:error, :data_not_received}
    end
  end

  ## Helpers

  defp wait_until_worker_has_left_pool(pool, name) do
    case name in Enum.map(:gproc_pool.worker_pool(pool), fn {n, _p} -> n end) do
      false -> :ok
      true -> Process.sleep(200) && wait_until_worker_has_left_pool(pool, name)
    end
  end

  def get_host_port(v) do
    elem(v, 1)
  end

  def get_local_peer_pid(v) do
    elem(v, 0)
  end

  def get_local_channels(v) do
    elem(v, 1)
  end

  def get_remote_peer_pid(v) do
    elem(v, 2)
  end

  def get_remote_channels(v) do
    elem(v, 3)
  end

  def get_channel(id, channels) do
    {:ok, channel} = Map.fetch(channels, id)
    channel
  end
end
