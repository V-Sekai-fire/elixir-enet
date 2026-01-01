defmodule EnetCore do
  import Bitwise

  @moduledoc """
  ENet main API module.
  Converted from enet.erl.
  """

  require Logger

  alias EnetCore.Channel
  alias EnetCore.Host
  alias EnetCore.Peer
  alias EnetCore.Supervisor

  @type port_number :: 0..65_535
  @type mfargs :: {module(), atom(), [term()]}

  ## API

  @spec start_host(port_number(), mfargs() | function(), keyword()) ::
          {:ok, port_number()} | {:error, term()}
  def start_host(port, connect_fun, options) do
    {:ok, socket} = :gen_udp.open(port, Host.socket_options())
    {:ok, assigned_port} = :inet.port(socket)

    case Supervisor.start_host_supervisor(assigned_port, connect_fun, options) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _host_sup} ->
        host = :gproc.where({:n, :l, {:enet_host, assigned_port}})
        Host.give_socket(host, socket, :gen_udp)
        {:ok, assigned_port}
    end
  end

  @spec start_dtls_host(port_number(), mfargs() | function(), keyword()) ::
          {:ok, integer()} | {:error, term()}
  def start_dtls_host(port, connect_fun, options) do
    case Supervisor.start_host_dtls_supervisor(port, connect_fun, options) do
      {:error, reason} ->
        Logger.error("Startup dtls failure: #{inspect(reason)}")
        {:error, reason}

      {:ok, host_id} ->
        Logger.info("Startup dtls success")
        {:ok, host_id}
    end
  end

  @spec stop_host(port_number()) :: :ok
  def stop_host(host_port) do
    Supervisor.stop_host_supervisor(host_port)
  end

  @spec connect_peer(port_number(), String.t(), port_number(), pos_integer(), pos_integer()) ::
          {:ok, pid()} | {:error, atom()}
  def connect_peer(host_port, ip, remote_port, channel_count, data) do
    # Base implementation: use Host.connect
    host = :gproc.where({:n, :l, {:enet_host, host_port}})
    Host.connect(host, ip, remote_port, channel_count, data)
  end

  @spec connect_peer(port_number(), String.t(), port_number(), pos_integer()) ::
          {:ok, pid()} | {:error, atom()}
  def connect_peer(host_port, ip, remote_port, channel_count) do
    # Use random generated godot peer id as Data
    connect_peer(host_port, ip, remote_port, channel_count, rand_uint32_godot_peer())
  end

  @spec await_connect() :: {:ok, term()} | {:error, :timeout}
  def await_connect do
    receive do
      c = {:enet, :connect, _local_or_remote, _pc, _connect_id} -> {:ok, c}
    after
      1000 -> {:error, :timeout}
    end
  end

  @spec disconnect_peer(pid()) :: :ok
  def disconnect_peer(peer) do
    Peer.disconnect(peer)
  end

  @spec disconnect_peer_now(pid()) :: :ok
  def disconnect_peer_now(peer) do
    Peer.disconnect_now(peer)
  end

  @spec send_unsequenced(pid(), iodata()) :: :ok
  def send_unsequenced(channel, data) do
    Channel.send_unsequenced(channel, data)
  end

  @spec send_unreliable(pid(), iodata()) :: :ok
  def send_unreliable(channel, data) do
    Channel.send_unreliable(channel, data)
  end

  @spec send_reliable(pid(), iodata()) :: :ok
  def send_reliable(channel, data) do
    Channel.send_reliable(channel, data)
  end

  @spec broadcast_unsequenced(port_number(), integer(), iodata()) :: :ok
  def broadcast_unsequenced(host_port, channel_id, data) do
    broadcast(host_port, channel_id, data, &send_unsequenced/2)
  end

  @spec broadcast_unreliable(port_number(), integer(), iodata()) :: :ok
  def broadcast_unreliable(host_port, channel_id, data) do
    broadcast(host_port, channel_id, data, &send_unreliable/2)
  end

  @spec broadcast_reliable(port_number(), integer(), iodata()) :: :ok
  def broadcast_reliable(host_port, channel_id, data) do
    broadcast(host_port, channel_id, data, &send_reliable/2)
  end

  ## Internal functions

  defp broadcast(host_port, channel_id, data, send_fun) do
    peers = EnetCore.Pool.active_peers(host_port)

    Enum.each(peers, fn {_name, peer} ->
      channel = Peer.channel(peer, channel_id)
      send_fun.(channel, data)
    end)
  end

  defp rand_uint32_godot_peer do
    # Exclude 0 and 1, reserved for godot servers
    max = 0xFFFFFFFF - 1
    n = :rand.uniform(max) + 1
    # Godot requires it compatible with unsigned, since negative ID is used for exclusion
    n &&& 0x7FFFFFFF
  end
end
