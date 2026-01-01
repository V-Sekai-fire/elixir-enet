defmodule Enet.Host do
  @moduledoc """
  ENet host gen_server.
  Converted from enet_host.erl.
  """

  use GenServer
  require Logger
  import Bitwise

  alias Enet.Constants
  alias Enet.Peer
  alias Enet.PeerRecord
  alias Enet.PeerSupervisor
  alias Enet.Pool
  alias Enet.Protocol
  alias Enet.ProtocolDecoder
  alias Enet.ProtocolEncoder

  defstruct [
    :transport,
    :peername,
    :socket,
    :compressor,
    :connect_fun
  ]

  @null_peer_id 0xFFF

  ## API

  @spec start_link(integer(), function() | mfa(), keyword()) :: GenServer.on_start()
  def start_link(host_id, connect_fun, options) do
    GenServer.start_link(__MODULE__, {host_id, connect_fun, options}, [])
  end

  @spec socket_options() :: keyword()
  def socket_options do
    [:binary, {:active, false}, {:reuseaddr, false}, {:broadcast, true}]
  end

  @spec give_socket(pid(), term(), atom()) :: {:ok, pid()} | {:error, term()}
  def give_socket(host, socket, transport) do
    case transport.controlling_process(socket, host) do
      :ok ->
        Logger.info("Process transferred 1")
        GenServer.cast(host, {:give_socket, socket, transport})
        {:ok, host}

      {:error, reason} ->
        Logger.error("Failed to transfer process: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec connect(pid(), String.t(), integer(), integer(), integer()) ::
          {:ok, pid()} | {:error, atom()}
  def connect(host, ip, port, channel_count, data) do
    GenServer.call(host, {:connect, ip, port, channel_count, data})
  end

  @spec send_outgoing_commands(pid(), iodata(), String.t(), integer()) ::
          {:sent_time, integer()} | {:error, term()}
  def send_outgoing_commands(host, commands, ip, port) do
    send_outgoing_commands(host, commands, ip, port, @null_peer_id)
  end

  @spec send_outgoing_commands(pid(), iodata(), String.t(), integer(), integer()) ::
          {:sent_time, integer()} | {:error, term()}
  def send_outgoing_commands(host, commands, ip, port, peer_id) do
    GenServer.call(host, {:send_outgoing_commands, commands, ip, port, peer_id})
  end

  @spec get_port(pid()) :: integer() | false
  def get_port(host) do
    :gproc.get_value({:p, :l, :port}, host)
  end

  @spec get_incoming_bandwidth(pid()) :: integer() | false
  def get_incoming_bandwidth(host) do
    :gproc.get_value({:p, :l, :incoming_bandwidth}, host)
  end

  @spec get_outgoing_bandwidth(pid()) :: integer() | false
  def get_outgoing_bandwidth(host) do
    :gproc.get_value({:p, :l, :outgoing_bandwidth}, host)
  end

  @spec get_mtu(pid()) :: integer() | false
  def get_mtu(host) do
    :gproc.get_value({:p, :l, :mtu}, host)
  end

  @spec get_channel_limit(pid()) :: integer() | false
  def get_channel_limit(host) do
    :gproc.get_value({:p, :l, :channel_limit}, host)
  end

  ## GenServer callbacks

  @impl true
  def init({host_id, connect_fun, options}) do
    true = :gproc.reg({:n, :l, {:enet_host, host_id}})
    :yes = :global.register_name({:enet_host, host_id}, self())

    channel_limit =
      case Keyword.get(options, :channel_limit) do
        nil -> Constants.min_channel_count()
        limit -> limit
      end

    incoming_bandwidth =
      case Keyword.get(options, :incoming_bandwidth) do
        nil -> 0
        bandwidth -> bandwidth
      end

    outgoing_bandwidth =
      case Keyword.get(options, :outgoing_bandwidth) do
        nil -> 0
        bandwidth -> bandwidth
      end

    compressor =
      case Keyword.get(options, :compression_mode) do
        nil -> :none
        mode -> mode
      end

    true =
      :gproc.mreg(
        :p,
        :l,
        [
          {:port, host_id},
          {:channel_limit, channel_limit},
          {:incoming_bandwidth, incoming_bandwidth},
          {:outgoing_bandwidth, outgoing_bandwidth},
          {:mtu, Constants.host_default_mtu()}
        ]
      )

    {:ok,
     %__MODULE__{
       connect_fun: connect_fun,
       compressor: compressor,
       transport: nil,
       peername: nil,
       socket: nil
     }}
  end

  @impl true
  def handle_call({:connect, ip, port, channels, data}, _from, state) do
    %__MODULE__{connect_fun: connect_fun, socket: socket} = state
    local_port = get_port(self())

    case socket do
      nil ->
        # DTLS mode - create DTLS client connection first
        connect_dtls(ip, port, channels, data, local_port, connect_fun, state)

      _ ->
        # UDP mode - existing flow
        connect_udp(ip, port, channels, data, local_port, connect_fun, state)
    end
  end

  @impl true
  def handle_call({:send_outgoing_commands, c, ip, port, id}, _from, state) do
    %__MODULE__{compressor: compression_mode, socket: socket} = state

    case socket do
      nil ->
        Logger.warning("ENet Host: Cannot send - socket is undefined (DTLS mode?)")
        {:reply, {:error, :no_socket}, state}

      _ ->
        {compressed, commands} =
          case compression_mode do
            :none -> {0, c}
            compressor -> {1, compress(c, compressor)}
          end

        sent_time = get_time()

        ph = %Protocol.Header{
          compressed: compressed,
          peer_id: id,
          sent_time: sent_time
        }

        packet = [ProtocolEncoder.protocol_header(ph), commands]
        ip_addr = parse_ip(ip)
        ip_str = format_ip(ip_addr)
        Logger.debug("ENet Host: Sending UDP packet to #{ip_str}:#{port}, size=#{iolist_size(packet)}")

        :ok = :gen_udp.send(socket, ip_addr, port, packet)
        {:reply, {:sent_time, sent_time}, state}
    end
  end

  @impl true
  def handle_cast({:give_socket, socket, transport}, state) do
    # For UDP (gen_udp), use inet:setopts; for DTLS (ssl), use ssl:setopts
    case transport do
      :gen_udp ->
        :ok = :inet.setopts(socket, [{:active, true}])

      :ssl ->
        :ok = :ssl.setopts(socket, [{:active, true}])

      _ ->
        :ok = transport.setopts(socket, [{:active, true}])
    end

    # For UDP, peername is not available until a packet is received
    # For DTLS, peername is available after handshake
    peername =
      case transport do
        :gen_udp ->
          nil

        _ ->
          case transport.peername(socket) do
            {:ok, pn} -> pn
            _ -> nil
          end
      end

    Logger.info("Process transferred 2")
    {:noreply, %{state | socket: socket, transport: transport, peername: peername}}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl, _raw, packet}, state) do
    %__MODULE__{transport: t, socket: s, peername: p} = state
    Logger.debug("Inside host sup")
    Logger.debug("#{:esockd.format(p)} ← #{inspect(packet)}")
    t.async_send(s, packet)
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl_passive, _raw}, state) do
    %__MODULE__{transport: t, socket: s, peername: p} = state
    Logger.debug("#{:esockd.format(p)} → passive")
    t.setopts(s, [{:active, 100}])
    {:noreply, state}
  end

  @impl true
  def handle_info({:inet_reply, _raw, :ok}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl_closed, _raw}, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:ssl_error, _raw, reason}, state) do
    %__MODULE__{peername: p} = state
    Logger.error("#{:esockd.format(p)} error: #{inspect(reason)}")
    {:stop, reason, state}
  end

  @impl true
  def handle_info({:udp_error, _socket, reason}, state) do
    Logger.debug("ENet Host: UDP error: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, packet}, state) do
    demux_packet(socket, ip, port, packet, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:gproc, :unreg, _ref, {:n, :l, {:enet_peer, ref}}}, state) do
    # A Peer process has exited.
    # Remove it from the pool
    local_port = get_port(self())
    true = Pool.remove_peer(local_port, ref)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("terminating: #{inspect(reason)}")
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  ## Internal functions

  defp demux_packet(_socket, ip, port, packet, state) do
    # Received a UDP packet.
    # - Unpack the ENet protocol header
    # - Decompress the remaining packet if necessary
    # - Send the packet to the peer (ID in protocol header)
    %__MODULE__{
      compressor: compression_mode,
      connect_fun: connect_fun
    } = state

    {:ok,
     %Protocol.Header{
       compressed: is_compressed,
       peer_id: recipient_peer_id,
       sent_time: sent_time
     }, rest} = ProtocolDecoder.protocol_header(packet)

    commands =
      case is_compressed do
        0 -> rest
        1 -> decompress(rest, compression_mode)
      end

    local_port = get_port(self())

    case recipient_peer_id do
      @null_peer_id ->
        # No particular peer is the receiver of this packet.
        # Create a new peer.
        ref = make_ref()

        try do
          peer_id = Pool.add_peer(local_port, ref)

          peer = %PeerRecord{
            handshake_flow: :remote,
            peer_id: peer_id,
            ip: ip,
            port: port,
            name: ref,
            host: self(),
            manager_pid: self(),
            connect_fun: connect_fun
          }

          {:ok, pid} = start_peer(peer)
          Peer.recv_incoming_packet(pid, ip, sent_time, commands)
        catch
          :error, :pool_full -> {:error, :reached_peer_limit}
          :error, :exists -> {:error, :exists}
        end

      peer_id ->
        case Pool.pick_peer(local_port, peer_id) do
          # Unknown peer - drop the packet
          false ->
            :ok

          pid ->
            Peer.recv_incoming_packet(pid, ip, sent_time, commands)
        end
    end
  end

  defp get_time do
    :erlang.system_time(:millisecond) &&& 0xFFFF
  end

  defp start_peer(%PeerRecord{name: ref} = peer) do
    host_id = :gproc.get_value({:p, :l, :port}, self())
    peer_sup = :gproc.where({:n, :l, {:enet_peer_sup, host_id}})
    {:ok, pid} = PeerSupervisor.start_peer(peer_sup, peer)
    _ref = :gproc.monitor({:n, :l, {:enet_peer, ref}})
    {:ok, pid}
  end

  defp decompress(data, :zlib) do
    :zlib.uncompress(data)
  end

  defp decompress(_data, mode) do
    unsupported_compress_mode(mode)
  end

  defp compress(data, :zlib) do
    :zlib.compress(data)
  end

  defp compress(_data, mode) do
    unsupported_compress_mode(mode)
  end

  defp unsupported_compress_mode(mode) do
    Logger.error("Unsupported compression mode: #{inspect(mode)}")
  end

  defp parse_ip(ip) when is_binary(ip) do
    ip_str = :erlang.binary_to_list(ip)

    case :inet.parse_address(ip_str) do
      {:ok, addr} -> addr
      _ -> parse_ip_string(ip_str)
    end
  end

  defp parse_ip(ip) when is_list(ip) do
    case :inet.parse_address(ip) do
      {:ok, addr} -> addr
      _ -> parse_ip_string(ip)
    end
  end

  defp parse_ip(ip) when is_tuple(ip) do
    ip
  end

  defp parse_ip(_ip) do
    {127, 0, 0, 1}
  end

  defp parse_ip_string(ip_str) do
    parts = String.split(ip_str, ".")
    parts_int = Enum.map(parts, &String.to_integer/1)
    List.to_tuple(parts_int)
  end

  defp format_ip({a, b, c, d}) when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(ip), do: inspect(ip)

  defp iolist_size(data) when is_binary(data), do: byte_size(data)
  defp iolist_size(data) when is_list(data), do: :erlang.iolist_size(data)
  defp iolist_size(_), do: 0

  defp connect_udp(ip, port, channels, data, local_port, connect_fun, state) do
    ref = make_ref()

    reply =
      try do
        peer_id = Pool.add_peer(local_port, ref)

        peer = %PeerRecord{
          handshake_flow: :local,
          peer_id: peer_id,
          ip: ip,
          port: port,
          name: ref,
          host: self(),
          manager_pid: self(),
          channels: channels,
          connect_fun: connect_fun,
          connect_packet_data: data
        }

        start_peer(peer)
      catch
        :error, :pool_full -> {:error, :reached_peer_limit}
        :error, :exists -> {:error, :exists}
      end

    {:reply, reply, state}
  end

  defp connect_dtls(ip, port, channels, data, local_port, _connect_fun, state) do
    # Get DTLS connection supervisor for this host
    host_id = local_port
    conn_sup = :gproc.where({:n, :l, {SpatialNodeStoreAPI.GodotDtlsEchoConnSup, host_id}})

    case conn_sup do
      :undefined ->
        {:reply, {:error, :dtls_supervisor_not_found}, state}

      _ ->
        connect_dtls_with_supervisor(ip, port, channels, data, host_id, local_port, state)
    end
  end

  defp connect_dtls_with_supervisor(ip, port, channels, data, host_id, local_port, state) do
    # Get list of existing peers before starting DTLS client
    existing_peers = get_existing_peer_pids(local_port)

    # Start DTLS client connection (external API - don't modify)
    case SpatialNodeStoreAPI.GodotDtlsEchoConnSup.start_child_connect(
           host_id,
           ip,
           port,
           channels,
           data
         ) do
      {:ok, _dtls_client_pid} ->
        wait_for_dtls_peer_and_reply(ip, port, local_port, existing_peers, state)

      error ->
        {:reply, error, state}
    end
  end

  defp wait_for_dtls_peer_and_reply(ip, port, local_port, existing_peers, state) do
    # Wait for DTLS client to complete handshake and create peer
    # The DTLS client will create peer via :client_add_peer message
    # We need to wait for that peer to be created
    case wait_for_dtls_peer_creation(ip, port, local_port, existing_peers, 10_000) do
      {:ok, peer_pid} ->
        {:reply, {:ok, peer_pid}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp get_existing_peer_pids(local_port) do
    # Get all currently active peer PIDs
    case Pool.active_peers(local_port) do
      peers when is_list(peers) ->
        # Extract PIDs from {name, pid} tuples
        Enum.map(peers, fn {_name, pid} -> pid end)

      _ ->
        []
    end
  end

  defp wait_for_dtls_peer_creation(ip, port, local_port, existing_peers, timeout_ms) do
    # Wait for peer to be created by DTLS client
    # The peer is registered in gproc with {:n, :l, {:enet_peer, ref}}
    # We poll for new peers that weren't in the existing list
    start_time = System.monotonic_time(:millisecond)

    wait_for_peer_loop(ip, port, local_port, existing_peers, timeout_ms, start_time)
  end

  defp wait_for_peer_loop(ip, port, local_port, existing_peers, timeout_ms, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout_ms do
      {:error, :timeout}
    else
      # Check for new peers
      case find_new_peer(ip, port, local_port, existing_peers) do
        {:ok, peer_pid} ->
          {:ok, peer_pid}

        :not_found ->
          Process.sleep(50) # Poll every 50ms
          wait_for_peer_loop(ip, port, local_port, existing_peers, timeout_ms, start_time)
      end
    end
  end

  defp find_new_peer(_ip, _port, local_port, existing_peers) do
    # Get all active peers
    case Pool.active_peers(local_port) do
      peers when is_list(peers) ->
        # Find a peer that:
        # 1. Wasn't in the existing list
        # 2. Matches the connection (ip, port) - verify via peer state if possible
        new_peers =
          Enum.filter(peers, fn {_name, pid} ->
            not Enum.member?(existing_peers, pid) and Process.alive?(pid)
          end)

        case new_peers do
          [{_name, peer_pid} | _] ->
            # Found a new peer - verify it matches our connection
            # We can't easily query peer state without adding API, so we assume
            # the first new peer is ours (especially if only one connection is happening)
            # In practice, DTLS client creates exactly one peer per connection
            {:ok, peer_pid}

          [] ->
            :not_found
        end

      _ ->
        :not_found
    end
  end
end
