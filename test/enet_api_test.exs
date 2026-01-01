defmodule EnetCore.ApiTest do
  @moduledoc """
  ENet API tests.
  Converted from enet_api_SUITE.erl.
  """

  use ExUnit.Case, async: false

  alias EnetCore
  alias EnetCore.Protocol

  setup do
    # Ensure the application is started
    Application.ensure_all_started(:enet_core)
    :ok
  end

  test "local worker init error" do
    connect_fun = fn _peer_info -> {:error, :whatever} end
    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    ref = Process.monitor(local_peer)

    assert_receive {:DOWN, ^ref, :process, ^local_peer, {:worker_init_error, :whatever}}, 1000

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "local zero peer limit" do
    self_pid = self()
    connect_fun = fn _peer_info -> {:ok, self_pid} end
    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 0)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)

    assert {:error, :reached_peer_limit} =
             EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "remote zero peer limit" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 0)
    {:ok, _peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    # Should not receive peer info because remote host has zero peer limit
    refute_receive %{peer: _peer}, 200

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "broadcast connect" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 1)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "255.255.255.255", remote_host, 1)

    connect_id =
      receive do
        %{peer: ^local_peer, connect_id: c} -> c
      after
        1000 -> flunk("Timeout waiting for connect_id")
      end

    remote_peer =
      receive do
        %{peer: p, connect_id: ^connect_id} -> p
      after
        1000 -> flunk("Timeout waiting for remote_peer")
      end

    ref1 = Process.monitor(local_peer)
    ref2 = Process.monitor(remote_peer)

    :ok = EnetCore.disconnect_peer(local_peer)

    assert_receive {:enet, :disconnected, :local, ^local_peer, ^connect_id}, 1000
    assert_receive {:enet, :disconnected, :remote, ^remote_peer, ^connect_id}, 1000
    assert_receive {:DOWN, ^ref1, :process, ^local_peer, :normal}, 1000
    assert_receive {:DOWN, ^ref2, :process, ^remote_peer, :normal}, 1000

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "local disconnect" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    connect_id =
      receive do
        %{peer: ^local_peer, connect_id: c} -> c
      after
        1000 -> flunk("Timeout waiting for connect_id")
      end

    remote_peer =
      receive do
        %{peer: p, connect_id: ^connect_id} -> p
      after
        1000 -> flunk("Timeout waiting for remote_peer")
      end

    ref1 = Process.monitor(local_peer)
    ref2 = Process.monitor(remote_peer)

    :ok = EnetCore.disconnect_peer(local_peer)

    assert_receive {:enet, :disconnected, :local, ^local_peer, ^connect_id}, 1000
    assert_receive {:enet, :disconnected, :remote, ^remote_peer, ^connect_id}, 1000
    assert_receive {:DOWN, ^ref1, :process, ^local_peer, :normal}, 1000
    assert_receive {:DOWN, ^ref2, :process, ^remote_peer, :normal}, 1000

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "remote disconnect" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    connect_id =
      receive do
        %{peer: ^local_peer, connect_id: c} -> c
      after
        1000 -> flunk("Timeout waiting for connect_id")
      end

    remote_peer =
      receive do
        %{peer: p, connect_id: ^connect_id} -> p
      after
        1000 -> flunk("Timeout waiting for remote_peer")
      end

    ref1 = Process.monitor(local_peer)
    ref2 = Process.monitor(remote_peer)

    :ok = EnetCore.disconnect_peer(remote_peer)

    assert_receive {:enet, :disconnected, :local, _local_peer, ^connect_id}, 1000
    assert_receive {:enet, :disconnected, :remote, _remote_peer, ^connect_id}, 1000
    assert_receive {:DOWN, ^ref1, :process, ^local_peer, :normal}, 1000
    assert_receive {:DOWN, ^ref2, :process, ^remote_peer, :normal}, 1000

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "unsequenced messages" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    {connect_id, local_channels} =
      receive do
        %{peer: ^local_peer, channels: lcs, connect_id: c} -> {c, lcs}
      after
        1000 -> flunk("Timeout waiting for local channels")
      end

    remote_channels =
      receive do
        %{channels: rcs, connect_id: ^connect_id} -> rcs
      after
        1000 -> flunk("Timeout waiting for remote channels")
      end

    {:ok, local_channel1} = Map.fetch(local_channels, 0)
    {:ok, remote_channel1} = Map.fetch(remote_channels, 0)

    :ok = EnetCore.send_unsequenced(local_channel1, <<"local->remote">>)
    :ok = EnetCore.send_unsequenced(remote_channel1, <<"remote->local">>)

    assert_receive {:enet, 0, <<"local->remote">>}, 500
    assert_receive {:enet, 0, <<"remote->local">>}, 500

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "unreliable messages" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    {connect_id, local_channels} =
      receive do
        %{peer: ^local_peer, channels: lcs, connect_id: c} -> {c, lcs}
      after
        1000 -> flunk("Timeout waiting for local channels")
      end

    remote_channels =
      receive do
        %{channels: rcs, connect_id: ^connect_id} -> rcs
      after
        1000 -> flunk("Timeout waiting for remote channels")
      end

    {:ok, local_channel1} = Map.fetch(local_channels, 0)
    {:ok, remote_channel1} = Map.fetch(remote_channels, 0)

    :ok = EnetCore.send_unreliable(local_channel1, <<"local->remote 1">>)
    :ok = EnetCore.send_unreliable(remote_channel1, <<"remote->local 1">>)
    :ok = EnetCore.send_unreliable(local_channel1, <<"local->remote 2">>)
    :ok = EnetCore.send_unreliable(remote_channel1, <<"remote->local 2">>)

    assert_receive {:enet, 0, <<"local->remote 1">>}, 500
    assert_receive {:enet, 0, <<"remote->local 1">>}, 500
    assert_receive {:enet, 0, <<"local->remote 2">>}, 500
    assert_receive {:enet, 0, <<"remote->local 2">>}, 500

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "reliable messages" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, local_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, remote_host} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, local_peer} = EnetCore.connect_peer(local_host, "127.0.0.1", remote_host, 1)

    {connect_id, local_channels} =
      receive do
        %{peer: ^local_peer, channels: lcs, connect_id: c} -> {c, lcs}
      after
        1000 -> flunk("Timeout waiting for local channels")
      end

    remote_channels =
      receive do
        %{channels: rcs, connect_id: ^connect_id} -> rcs
      after
        1000 -> flunk("Timeout waiting for remote channels")
      end

    {:ok, local_channel1} = Map.fetch(local_channels, 0)
    {:ok, remote_channel1} = Map.fetch(remote_channels, 0)

    :ok = EnetCore.send_reliable(local_channel1, <<"local->remote 1">>)
    :ok = EnetCore.send_reliable(remote_channel1, <<"remote->local 1">>)
    :ok = EnetCore.send_reliable(local_channel1, <<"local->remote 2">>)
    :ok = EnetCore.send_reliable(remote_channel1, <<"remote->local 2">>)

    assert_receive {:enet, 0, <<"local->remote 1">>}, 500
    assert_receive {:enet, 0, <<"remote->local 1">>}, 500
    assert_receive {:enet, 0, <<"local->remote 2">>}, 500
    assert_receive {:enet, 0, <<"remote->local 2">>}, 500

    :ok = EnetCore.stop_host(local_host)
    :ok = EnetCore.stop_host(remote_host)
  end

  test "unsequenced broadcast" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, host1} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host2} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host3} = EnetCore.start_host(0, connect_fun, peer_limit: 8)

    {:ok, peer12} = EnetCore.connect_peer(host1, "127.0.0.1", host2, 1)

    connect_id12 =
      receive do
        %{peer: ^peer12, connect_id: cid12} -> cid12
      after
        1000 -> flunk("Timeout waiting for connect_id12")
      end

    assert_receive %{connect_id: ^connect_id12}, 1000

    {:ok, peer23} = EnetCore.connect_peer(host2, "127.0.0.1", host3, 1)

    connect_id23 =
      receive do
        %{peer: ^peer23, connect_id: cid23} -> cid23
      after
        1000 -> flunk("Timeout waiting for connect_id23")
      end

    assert_receive %{connect_id: ^connect_id23}, 1000

    {:ok, peer31} = EnetCore.connect_peer(host3, "127.0.0.1", host1, 1)

    connect_id31 =
      receive do
        %{peer: ^peer31, connect_id: cid31} -> cid31
      after
        1000 -> flunk("Timeout waiting for connect_id31")
      end

    assert_receive %{connect_id: ^connect_id31}, 1000

    :ok = EnetCore.broadcast_unsequenced(host1, 0, <<"host1->broadcast">>)
    :ok = EnetCore.broadcast_unsequenced(host2, 0, <<"host2->broadcast">>)
    :ok = EnetCore.broadcast_unsequenced(host3, 0, <<"host3->broadcast">>)

    # Each host should receive 2 broadcast messages (from the other 2 hosts)
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500

    :ok = EnetCore.stop_host(host1)
    :ok = EnetCore.stop_host(host2)
    :ok = EnetCore.stop_host(host3)
  end

  test "unreliable broadcast" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, host1} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host2} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host3} = EnetCore.start_host(0, connect_fun, peer_limit: 8)

    {:ok, peer12} = EnetCore.connect_peer(host1, "127.0.0.1", host2, 1)

    connect_id12 =
      receive do
        %{peer: ^peer12, connect_id: cid12} -> cid12
      after
        1000 -> flunk("Timeout waiting for connect_id12")
      end

    assert_receive %{connect_id: ^connect_id12}, 1000

    {:ok, peer23} = EnetCore.connect_peer(host2, "127.0.0.1", host3, 1)

    connect_id23 =
      receive do
        %{peer: ^peer23, connect_id: cid23} -> cid23
      after
        1000 -> flunk("Timeout waiting for connect_id23")
      end

    assert_receive %{connect_id: ^connect_id23}, 1000

    {:ok, peer31} = EnetCore.connect_peer(host3, "127.0.0.1", host1, 1)

    connect_id31 =
      receive do
        %{peer: ^peer31, connect_id: cid31} -> cid31
      after
        1000 -> flunk("Timeout waiting for connect_id31")
      end

    assert_receive %{connect_id: ^connect_id31}, 1000

    :ok = EnetCore.broadcast_unreliable(host1, 0, <<"host1->broadcast">>)
    :ok = EnetCore.broadcast_unreliable(host2, 0, <<"host2->broadcast">>)
    :ok = EnetCore.broadcast_unreliable(host3, 0, <<"host3->broadcast">>)

    # Each host should receive 2 broadcast messages (from the other 2 hosts)
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500

    :ok = EnetCore.stop_host(host1)
    :ok = EnetCore.stop_host(host2)
    :ok = EnetCore.stop_host(host3)
  end

  test "reliable broadcast" do
    self_pid = self()

    connect_fun = fn peer_info ->
      send(self_pid, peer_info)
      {:ok, self_pid}
    end

    {:ok, host1} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host2} = EnetCore.start_host(0, connect_fun, peer_limit: 8)
    {:ok, host3} = EnetCore.start_host(0, connect_fun, peer_limit: 8)

    {:ok, peer12} = EnetCore.connect_peer(host1, "127.0.0.1", host2, 1)

    connect_id12 =
      receive do
        %{peer: ^peer12, connect_id: cid12} -> cid12
      after
        1000 -> flunk("Timeout waiting for connect_id12")
      end

    assert_receive %{connect_id: ^connect_id12}, 1000

    {:ok, peer23} = EnetCore.connect_peer(host2, "127.0.0.1", host3, 1)

    connect_id23 =
      receive do
        %{peer: ^peer23, connect_id: cid23} -> cid23
      after
        1000 -> flunk("Timeout waiting for connect_id23")
      end

    assert_receive %{connect_id: ^connect_id23}, 1000

    {:ok, peer31} = EnetCore.connect_peer(host3, "127.0.0.1", host1, 1)

    connect_id31 =
      receive do
        %{peer: ^peer31, connect_id: cid31} -> cid31
      after
        1000 -> flunk("Timeout waiting for connect_id31")
      end

    assert_receive %{connect_id: ^connect_id31}, 1000

    :ok = EnetCore.broadcast_reliable(host1, 0, <<"host1->broadcast">>)
    :ok = EnetCore.broadcast_reliable(host2, 0, <<"host2->broadcast">>)
    :ok = EnetCore.broadcast_reliable(host3, 0, <<"host3->broadcast">>)

    # Each host should receive 2 broadcast messages (from the other 2 hosts)
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host1->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host2->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500
    assert_receive {:enet, 0, <<"host3->broadcast">>}, 500

    :ok = EnetCore.stop_host(host1)
    :ok = EnetCore.stop_host(host2)
    :ok = EnetCore.stop_host(host3)
  end
end
