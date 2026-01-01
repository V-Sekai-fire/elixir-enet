defmodule EnetCore.Peer do
  @moduledoc """
  ENet peer gen_statem.
  Converted from enet_peer.erl.

  This is a state machine with the following states:
  - :connecting - Client is connecting to a server
  - :acknowledging_connect - Server received connect, sending verify
  - :acknowledging_verify_connect - Client received verify, waiting for ack
  - :verifying_connect - Server sent verify, waiting for ack
  - :connected - Connection is established
  - :disconnecting - Disconnection in progress
  """

  @behaviour :gen_statem
  require Logger

  alias EnetCore.Channel
  alias EnetCore.Command
  alias EnetCore.Constants
  alias EnetCore.Disconnector
  alias EnetCore.Host
  alias EnetCore.PeerRecord
  alias EnetCore.Pool
  alias EnetCore.Protocol
  alias EnetCore.ProtocolDecoder
  alias EnetCore.ProtocolEncoder

  defstruct [
    :local_port,
    :ip,
    :port,
    :manager_name,
    :manager_pid,
    :remote_peer_id,
    :peer_id,
    :connect_id,
    :host,
    :channel_count,
    :channels,
    :worker,
    :connect_fun,
    :connect_packet_data,
    :connect_timer_id,
    incoming_session_id: 0xFF,
    outgoing_session_id: 0xFF,
    incoming_bandwidth: 0,
    outgoing_bandwidth: 0,
    window_size: nil,
    packet_throttle_interval: Constants.peer_packet_throttle_interval(),
    packet_throttle_acceleration: Constants.peer_packet_throttle_acceleration(),
    packet_throttle_deceleration: Constants.peer_packet_throttle_deceleration(),
    outgoing_reliable_sequence_number: 1,
    incoming_unsequenced_group: 0,
    outgoing_unsequenced_group: 1,
    unsequenced_window: 0
  ]

  ## API

  @spec start_link(integer(), PeerRecord.t()) :: GenServer.on_start()
  def start_link(host_id, peer) do
    :gen_statem.start_link(__MODULE__, [host_id, peer], [])
  end

  @spec disconnect(pid()) :: :ok
  def disconnect(peer) do
    :gen_statem.cast(peer, :disconnect)
  end

  @spec disconnect_now(pid()) :: :ok
  def disconnect_now(peer) do
    :gen_statem.cast(peer, :disconnect_now)
  end

  @spec channels(pid()) :: map()
  def channels(peer) do
    :gen_statem.call(peer, :channels)
  end

  @spec channel(pid(), integer()) :: pid()
  def channel(peer, id) do
    :gen_statem.call(peer, {:channel, id})
  end

  @spec recv_incoming_packet(pid(), String.t(), integer(), binary()) :: :ok
  def recv_incoming_packet(peer, from_ip, sent_time, packet) do
    :gen_statem.cast(peer, {:incoming_packet, from_ip, sent_time, packet})
  end

  @spec send_command(pid(), {Protocol.CommandHeader.t(), term()}) :: :ok
  def send_command(peer, {h, c}) do
    :gen_statem.cast(peer, {:outgoing_command, {h, c}})
  end

  @spec get_connect_id(pid()) :: integer() | false
  def get_connect_id(peer) do
    :gproc.get_value({:p, :l, :connect_id}, peer)
  end

  @spec get_mtu(pid()) :: integer() | false
  def get_mtu(peer) do
    :gproc.get_value({:p, :l, :mtu}, peer)
  end

  @spec get_name(pid()) :: term() | false
  def get_name(peer) do
    :gproc.get_value({:p, :l, :name}, peer)
  end

  @spec get_peer_id(pid()) :: integer() | false
  def get_peer_id(peer) do
    :gproc.get_value({:p, :l, :peer_id}, peer)
  end

  @spec get_pool(pid()) :: integer()
  def get_pool(peer) do
    :gen_statem.call(peer, :pool)
  end

  @spec get_pool_worker_id(pid()) :: integer() | false
  def get_pool_worker_id(peer) do
    :gen_statem.call(peer, :pool_worker_id)
  end

  ## gen_statem callbacks

  @impl :gen_statem
  def init([local_port, %PeerRecord{handshake_flow: :local} = p]) do
    # The client application wants to connect to a remote peer.
    # - Send a Connect command to the remote peer (use peer ID)
    # - Start in the 'connecting' state
    %PeerRecord{
      peer_id: peer_id,
      ip: ip,
      port: port,
      name: ref,
      manager_name: manager_name,
      manager_pid: manager_pid,
      host: host,
      channels: n,
      connect_fun: connect_fun,
      connect_packet_data: packet_data
    } = p

    Pool.connect_peer(local_port, ref)
    :gproc.reg({:n, :l, {:enet_peer, ref}})
    :gproc.reg({:p, :l, :name}, ref)
    :gproc.reg({:p, :l, :peer_id}, peer_id)

    state = %__MODULE__{
      host: host,
      local_port: local_port,
      ip: ip,
      port: port,
      manager_name: manager_name,
      manager_pid: manager_pid,
      peer_id: peer_id,
      channel_count: n,
      connect_fun: connect_fun,
      connect_packet_data: packet_data
    }

    {:ok, :connecting, state}
  end

  @impl :gen_statem
  def init([local_port, %PeerRecord{handshake_flow: :remote} = p]) do
    # A remote peer wants to connect to the client application.
    # - Start in the 'acknowledging_connect' state
    # - Handle the received Connect command
    %PeerRecord{
      peer_id: peer_id,
      ip: ip,
      port: port,
      name: ref,
      manager_name: manager_name,
      manager_pid: manager_pid,
      host: host,
      connect_fun: connect_fun,
      connect_packet_data: packet_data
    } = p

    Pool.connect_peer(local_port, ref)
    :gproc.reg({:n, :l, {:enet_peer, ref}})
    :gproc.reg({:p, :l, :name}, ref)
    :gproc.reg({:p, :l, :peer_id}, peer_id)

    state = %__MODULE__{
      host: host,
      local_port: local_port,
      ip: ip,
      port: port,
      peer_id: peer_id,
      manager_name: manager_name,
      manager_pid: manager_pid,
      connect_fun: connect_fun,
      connect_packet_data: packet_data
    }

    {:ok, :acknowledging_connect, state}
  end

  @impl :gen_statem
  def callback_mode do
    [:state_functions, :state_enter]
  end

  ## Connecting state

  @impl :gen_statem
  def connecting(:enter, _old_state, state) do
    # Sending the initial Connect command.
    %__MODULE__{
      host: host,
      manager_pid: manager_pid,
      channel_count: channel_count,
      ip: ip,
      port: port,
      peer_id: peer_id,
      incoming_session_id: incoming_session_id,
      outgoing_session_id: outgoing_session_id,
      packet_throttle_interval: packet_throttle_interval,
      packet_throttle_acceleration: packet_throttle_acceleration,
      packet_throttle_deceleration: packet_throttle_deceleration,
      outgoing_reliable_sequence_number: sequence_nr,
      connect_packet_data: packet_data
    } = state

    incoming_bandwidth = Host.get_incoming_bandwidth(host)
    outgoing_bandwidth = Host.get_outgoing_bandwidth(host)
    mtu = Host.get_mtu(host)
    :gproc.reg({:p, :l, :mtu}, mtu)

    <<connect_id::32>> = :crypto.strong_rand_bytes(4)

    {connect_h, connect_c} =
      Command.connect(
        peer_id,
        incoming_session_id,
        outgoing_session_id,
        channel_count,
        mtu,
        incoming_bandwidth,
        outgoing_bandwidth,
        packet_throttle_interval,
        packet_throttle_acceleration,
        packet_throttle_deceleration,
        connect_id,
        sequence_nr,
        packet_data
      )

    h_bin = ProtocolEncoder.command_header(connect_h)
    c_bin = ProtocolEncoder.command(connect_c)
    data = [h_bin, c_bin]

    Logger.info(
      "ENet Peer: Sending CONNECT command to #{ip}:#{port} via ManagerPid #{inspect(manager_pid)}"
    )

    sent_time =
      case send_outgoing_commands(manager_pid, data, ip, port) do
        {:sent_time, st} ->
          Logger.info("ENet Peer: CONNECT command sent, SentTime=#{st}")
          st

        {:error, :handshake_in_progress} ->
          # DTLS handshake not complete yet - wait and retry
          Logger.info("ENet Peer: DTLS handshake in progress, waiting...")
          Process.sleep(200)

          case send_outgoing_commands(manager_pid, data, ip, port) do
            {:sent_time, retry_st} ->
              Logger.info("ENet Peer: CONNECT command sent on retry, SentTime=#{retry_st}")
              retry_st

            retry_error ->
              Logger.warning(
                "ENet Peer: Retry failed: #{inspect(retry_error)}, using fallback time"
              )

              :erlang.system_time(:millisecond)
          end

        {:error, reason} ->
          Logger.warning(
            "ENet Peer: Failed to send CONNECT command: #{inspect(reason)}, using fallback time"
          )

          :erlang.system_time(:millisecond)
      end

    channel_id = 0xFF

    connect_timeout =
      make_resend_timer(channel_id, sent_time, sequence_nr, Constants.peer_timeout_minimum(), data)

    connect_timer_id = {channel_id, sent_time, sequence_nr}

    new_state = %{
      state
      | outgoing_reliable_sequence_number: sequence_nr + 1,
        connect_id: connect_id,
        connect_timer_id: connect_timer_id
    }

    {:keep_state, new_state, [connect_timeout]}
  end

  @impl :gen_statem
  def connecting(:cast, {:incoming_command, {h, %Protocol.Acknowledge{} = c}}, state) do
    # Received an Acknowledge command in the 'connecting' state.
    # - Verify that the acknowledge is correct
    # - Change state to 'acknowledging_verify_connect'
    %Protocol.CommandHeader{channel_id: channel_id} = h

    %Protocol.Acknowledge{
      received_reliable_sequence_number: sequence_number,
      received_sent_time: sent_time
    } = c

    canceled_timeout = cancel_resend_timer(channel_id, sent_time, sequence_number)
    {:next_state, :acknowledging_verify_connect, state, [canceled_timeout]}
  end

  @impl :gen_statem
  def connecting(:cast, {:incoming_command, {h, %Protocol.VerifyConnect{} = c}}, state) do
    # cancel the CONNECT retry
    %__MODULE__{connect_timer_id: connect_timer_id} = state
    {channel_id, sent_time, sequence_nr} = connect_timer_id
    canceled_timeout = cancel_resend_timer(channel_id, sent_time, sequence_nr)
    new_state = %{state | connect_timer_id: nil}
    # now jump into acknowledging_verify_connect *and* immediately
    # re‐fire the same verify_connect event there:
    {:next_state, :acknowledging_verify_connect, new_state,
     [{:next_event, :cast, {:incoming_command, {h, c}}}, canceled_timeout]}
  end

  @impl :gen_statem
  def connecting({:timeout, {_channel_id, _sent_time, _sequence_number}}, _data, _state) do
    Logger.debug("connection timeout")
    {:stop, :timeout}
  end

  @impl :gen_statem
  def connecting(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## Acknowledging Connect state

  @impl :gen_statem
  def acknowledging_connect(:enter, _old_state, state) do
    {:keep_state, state}
  end

  @impl :gen_statem
  def acknowledging_connect(:cast, {:incoming_command, {_h, %Protocol.Connect{} = c}}, state) do
    # Received a Connect command.
    # - Verify that the data is sane (TODO)
    # - Send a VerifyConnect command (use peer ID)
    # - Start in the 'verifying_connect' state
    %Protocol.Connect{
      outgoing_peer_id: remote_peer_id,
      mtu: mtu,
      window_size: window_size,
      channel_count: channel_count,
      incoming_bandwidth: incoming_bandwidth,
      outgoing_bandwidth: outgoing_bandwidth,
      packet_throttle_interval: packet_throttle_interval,
      packet_throttle_acceleration: packet_throttle_acceleration,
      packet_throttle_deceleration: packet_throttle_deceleration,
      connect_id: connect_id,
      data: packet_data
    } = c

    %__MODULE__{
      host: host,
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      peer_id: peer_id,
      incoming_session_id: incoming_session_id,
      outgoing_session_id: outgoing_session_id,
      outgoing_reliable_sequence_number: sequence_nr
    } = state

    :gproc.reg({:p, :l, :mtu}, mtu)
    host_channel_limit = Host.get_channel_limit(host)
    host_incoming_bandwidth = Host.get_incoming_bandwidth(host)
    host_outgoing_bandwidth = Host.get_outgoing_bandwidth(host)

    {vch, vcc} =
      Command.verify_connect(
        c,
        peer_id,
        incoming_session_id,
        outgoing_session_id,
        host_channel_limit,
        host_incoming_bandwidth,
        host_outgoing_bandwidth,
        sequence_nr
      )

    h_bin = ProtocolEncoder.command_header(vch)
    c_bin = ProtocolEncoder.command(vcc)
    data = [h_bin, c_bin]

    {:sent_time, sent_time} = send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)
    channel_id = 0xFF

    verify_connect_timeout =
      make_resend_timer(channel_id, sent_time, sequence_nr, Constants.peer_timeout_minimum(), data)

    new_state = %{
      state
      | remote_peer_id: remote_peer_id,
        connect_id: connect_id,
        incoming_bandwidth: incoming_bandwidth,
        outgoing_bandwidth: outgoing_bandwidth,
        window_size: window_size,
        packet_throttle_interval: packet_throttle_interval,
        packet_throttle_acceleration: packet_throttle_acceleration,
        packet_throttle_deceleration: packet_throttle_deceleration,
        outgoing_reliable_sequence_number: sequence_nr + 1,
        channel_count: channel_count,
        connect_packet_data: packet_data
    }

    {:next_state, :verifying_connect, new_state, [verify_connect_timeout]}
  end

  @impl :gen_statem
  def acknowledging_connect({:timeout, {_channel_id, _sent_time, _sequence_nr}}, _data, _state) do
    Logger.debug("acknowledgment timeout")
    {:stop, :timeout}
  end

  @impl :gen_statem
  def acknowledging_connect(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## Acknowledging Verify Connect state

  @impl :gen_statem
  def acknowledging_verify_connect(:enter, _old_state, state) do
    {:keep_state, state}
  end

  @impl :gen_statem
  def acknowledging_verify_connect(
        :cast,
        {:incoming_command, {_h, %Protocol.VerifyConnect{} = c}},
        state
      ) do
    # Received a Verify Connect command in the 'acknowledging_verify_connect' state.
    # - Verify that the data is correct
    # - Add the remote peer ID to the Peer Table
    # - Notify worker that we are connected
    # - Change state to 'connected'
    %Protocol.VerifyConnect{
      outgoing_peer_id: remote_peer_id,
      mtu: remote_mtu,
      channel_count: remote_channel_count,
      packet_throttle_interval: throttle_interval,
      packet_throttle_acceleration: throttle_acceleration,
      packet_throttle_deceleration: throttle_deceleration,
      connect_id: connect_id
    } = c

    %__MODULE__{channel_count: local_channel_count} = state
    local_mtu = get_mtu(self())

    # Calculate and validate Session IDs
    recv_bandwidth_limits = %Protocol.BandwidthLimit{
      incoming_bandwidth: c.incoming_bandwidth,
      outgoing_bandwidth: c.outgoing_bandwidth
    }

    if local_channel_count == remote_channel_count and local_mtu == remote_mtu and
         state.packet_throttle_interval == throttle_interval and
         state.packet_throttle_acceleration == throttle_acceleration and
         state.packet_throttle_deceleration == throttle_deceleration and
         state.connect_id == connect_id do
      new_state = %{state | remote_peer_id: remote_peer_id}
      # Set incoming_bandwidth, outgoing_bandwidth, window_size with Bandwidth limit cast for now
      {:next_state, :connected, new_state,
       [{:next_event, :cast, {:incoming_command, {nil, recv_bandwidth_limits}}}]}
    else
      {:stop, :connect_verification_failed, state}
    end
  end

  @impl :gen_statem
  def acknowledging_verify_connect(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## Verifying Connect state

  @impl :gen_statem
  def verifying_connect(:enter, _old_state, state) do
    {:keep_state, state}
  end

  @impl :gen_statem
  def verifying_connect(:cast, {:incoming_command, {h, %Protocol.Acknowledge{} = c}}, state) do
    # Received an Acknowledge command in the 'verifying_connect' state.
    # - Verify that the acknowledge is correct
    # - Notify worker that a new peer has been connected
    # - Change to 'connected' state
    %Protocol.CommandHeader{channel_id: channel_id} = h

    %Protocol.Acknowledge{
      received_reliable_sequence_number: sequence_number,
      received_sent_time: sent_time
    } = c

    canceled_timeout = cancel_resend_timer(channel_id, sent_time, sequence_number)
    {:next_state, :connected, state, [canceled_timeout]}
  end

  @impl :gen_statem
  def verifying_connect(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## Connected state

  @impl :gen_statem
  def connected(:enter, _old_state, state) do
    %__MODULE__{
      local_port: local_port,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id,
      connect_id: connect_id,
      channel_count: n,
      connect_fun: connect_fun,
      connect_packet_data: packet_data
    } = state

    true =
      :gproc.mreg(:p, :l, [
        {:connect_id, connect_id},
        {:remote_host_port, port},
        {:remote_peer_id, remote_peer_id}
      ])

    :ok = Disconnector.set_trigger(local_port, remote_peer_id, ip, port)
    channels = start_channels(n)

    peer_info = %{
      ip: ip,
      port: port,
      peer: self(),
      channels: channels,
      connect_id: connect_id,
      connect_packet_data: packet_data
    }

    case start_worker(connect_fun, peer_info) do
      {:error, reason} ->
        {:stop, {:worker_init_error, reason}, state}

      {:ok, worker} ->
        _ref = Process.monitor(worker)

        Enum.each(Map.values(channels), fn c ->
          Channel.set_worker(c, worker)
        end)

        new_state = %{state | channels: channels, worker: worker}
        send_timeout = reset_send_timer()
        recv_timeout = reset_recv_timer()
        {:keep_state, new_state, [send_timeout, recv_timeout]}
    end
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {_h, %Protocol.Ping{}}}, state) do
    # Received PING.
    # - Reset the receive-timer
    recv_timeout = reset_recv_timer()
    {:keep_state, state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {h, %Protocol.Acknowledge{} = c}}, state) do
    # Received an Acknowledge command.
    # - Verify that the acknowledge is correct
    # - Reset the receive-timer
    %Protocol.CommandHeader{channel_id: channel_id} = h

    %Protocol.Acknowledge{
      received_reliable_sequence_number: sequence_number,
      received_sent_time: sent_time
    } = c

    canceled_timeout = cancel_resend_timer(channel_id, sent_time, sequence_number)
    recv_timeout = reset_recv_timer()
    {:keep_state, state, [canceled_timeout, recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {_h, %Protocol.BandwidthLimit{} = c}}, state) do
    # Received Bandwidth Limit command.
    # - Set bandwidth limit
    # - Reset the receive-timer
    %Protocol.BandwidthLimit{
      incoming_bandwidth: incoming_bandwidth,
      outgoing_bandwidth: outgoing_bandwidth
    } = c

    %__MODULE__{host: host} = state
    host_outgoing_bandwidth = Host.get_outgoing_bandwidth(host)

    w_size =
      case {incoming_bandwidth, host_outgoing_bandwidth} do
        {0, 0} -> Constants.max_window_size()
        {0, h} -> div(Constants.min_window_size() * h, Constants.peer_window_size_scale())
        {p, 0} -> div(Constants.min_window_size() * p, Constants.peer_window_size_scale())
        {p, h} -> div(Constants.min_window_size() * min(p, h), Constants.peer_window_size_scale())
      end

    new_state = %{
      state
      | incoming_bandwidth: incoming_bandwidth,
        outgoing_bandwidth: outgoing_bandwidth,
        window_size:
          max(Constants.min_window_size(), min(Constants.max_window_size(), trunc(w_size)))
    }

    recv_timeout = reset_recv_timer()
    {:keep_state, new_state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {_h, %Protocol.ThrottleConfigure{} = c}}, state) do
    # Received Throttle Configure command.
    # - Set throttle configuration
    # - Reset the receive-timer
    %Protocol.ThrottleConfigure{
      packet_throttle_interval: interval,
      packet_throttle_acceleration: acceleration,
      packet_throttle_deceleration: deceleration
    } = c

    new_state = %{
      state
      | packet_throttle_interval: interval,
        packet_throttle_acceleration: acceleration,
        packet_throttle_deceleration: deceleration
    }

    recv_timeout = reset_recv_timer()
    {:keep_state, new_state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {h, %Protocol.Unsequenced{} = c}}, state) do
    # Received Send Unsequenced command.
    # - Forward the command to the relevant channel
    # - Reset the receive-timer
    %Protocol.CommandHeader{channel_id: channel_id} = h
    %__MODULE__{channels: channels} = state
    channel = Map.get(channels, channel_id)
    :ok = Channel.recv_unsequenced(channel, {h, c})
    recv_timeout = reset_recv_timer()
    {:keep_state, state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {h, %Protocol.Unreliable{} = c}}, state) do
    # Received Send Unreliable command.
    # - Forward the command to the relevant channel
    # - Reset the receive-timer
    %Protocol.CommandHeader{channel_id: channel_id} = h
    %__MODULE__{channels: channels} = state
    channel = Map.get(channels, channel_id)
    :ok = Channel.recv_unreliable(channel, {h, c})
    recv_timeout = reset_recv_timer()
    {:keep_state, state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {h, %Protocol.Reliable{} = c}}, state) do
    # Received Send Reliable command.
    # - Forward the command to the relevant channel
    # - Reset the receive-timer
    %Protocol.CommandHeader{channel_id: channel_id} = h
    %__MODULE__{channels: channels} = state
    channel = Map.get(channels, channel_id)
    :ok = Channel.recv_reliable(channel, {h, c})
    recv_timeout = reset_recv_timer()
    {:keep_state, state, [recv_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:incoming_command, {_h, %Protocol.Disconnect{}}}, state) do
    # Received Disconnect command.
    # - Notify worker application
    # - Stop
    %__MODULE__{
      worker: worker,
      local_port: local_port,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id,
      connect_id: connect_id
    } = state

    :ok = Disconnector.unset_trigger(local_port, remote_peer_id, ip, port)
    send(worker, {:enet, :disconnected, :remote, self(), connect_id})
    {:stop, :normal, state}
  end

  @impl :gen_statem
  def connected(:cast, {:outgoing_command, {h, %Protocol.Unsequenced{} = c}}, state) do
    # Sending an Unsequenced, unreliable command.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id,
      outgoing_unsequenced_group: group
    } = state

    c1 = %{c | group: group}
    h_bin = ProtocolEncoder.command_header(h)
    c_bin = ProtocolEncoder.command(c1)
    data = [h_bin, c_bin]

    {:sent_time, _sent_time} = send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)
    new_state = %{state | outgoing_unsequenced_group: group + 1}
    send_timeout = reset_send_timer()
    {:keep_state, new_state, [send_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:outgoing_command, {h, %Protocol.Unreliable{} = c}}, state) do
    # Sending a Sequenced, unreliable command.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    h_bin = ProtocolEncoder.command_header(h)
    c_bin = ProtocolEncoder.command(c)
    data = [h_bin, c_bin]

    {:sent_time, _sent_time} = send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)
    send_timeout = reset_send_timer()
    {:keep_state, state, [send_timeout]}
  end

  @impl :gen_statem
  def connected(:cast, {:outgoing_command, {h, %Protocol.Reliable{} = c}}, state) do
    # Sending a Sequenced, reliable command.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    %Protocol.CommandHeader{
      channel_id: channel_id,
      reliable_sequence_number: sequence_nr
    } = h

    h_bin = ProtocolEncoder.command_header(h)
    c_bin = ProtocolEncoder.command(c)
    data = [h_bin, c_bin]

    {:sent_time, sent_time} = send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)

    send_reliable_timeout =
      make_resend_timer(channel_id, sent_time, sequence_nr, Constants.peer_timeout_minimum(), data)

    send_timeout = reset_send_timer()
    {:keep_state, state, [send_reliable_timeout, send_timeout]}
  end

  @impl :gen_statem
  def connected(:info, {:enet, channel_id, c}, state) do
    # Received a message from a channel.
    %__MODULE__{worker: worker} = state

    if worker == self() do
      Logger.warning("Warning: Peer received {enet, ChannelID, C} but worker is self() - dropping")
      {:keep_state, state}
    else
      send(worker, {:enet, channel_id, c})
      {:keep_state, state}
    end
  end

  @impl :gen_statem
  def connected(:cast, :disconnect, state) do
    # Disconnecting.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    {h, c} = Command.sequenced_disconnect()
    h_bin = ProtocolEncoder.command_header(h)
    c_bin = ProtocolEncoder.command(c)
    data = [h_bin, c_bin]

    send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)
    {:next_state, :disconnecting, state}
  end

  @impl :gen_statem
  def connected(:cast, :disconnect_now, _state) do
    # Disconnecting immediately.
    {:stop, :normal}
  end

  @impl :gen_statem
  def connected({:timeout, {channel_id, sent_time, sequence_nr}}, data, state) do
    # A resend-timer was triggered.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)

    new_timeout =
      make_resend_timer(channel_id, sent_time, sequence_nr, Constants.peer_timeout_minimum(), data)

    send_timeout = reset_send_timer()
    {:keep_state, state, [new_timeout, send_timeout]}
  end

  @impl :gen_statem
  def connected({:timeout, :recv}, :ping, state) do
    # The receive-timer was triggered.
    %__MODULE__{
      worker: worker,
      connect_id: connect_id
    } = state

    Logger.debug("ping timeout")
    send(worker, {:enet, :ping_timeout, :remote, self(), connect_id})
    {:stop, :normal, state}
  end

  @impl :gen_statem
  def connected({:timeout, :send}, :ping, state) do
    # The send-timer was triggered.
    %__MODULE__{
      manager_pid: manager_pid,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    {h, c} = Command.ping()
    h_bin = ProtocolEncoder.command_header(h)
    c_bin = ProtocolEncoder.command(c)
    data = [h_bin, c_bin]

    {:sent_time, _sent_time} = send_outgoing_commands(manager_pid, data, ip, port, remote_peer_id)
    send_timeout = reset_send_timer()
    {:keep_state, state, [send_timeout]}
  end

  @impl :gen_statem
  def connected(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## Disconnecting state

  @impl :gen_statem
  def disconnecting(:enter, _old_state, state) do
    %__MODULE__{
      local_port: local_port,
      ip: ip,
      port: port,
      remote_peer_id: remote_peer_id
    } = state

    :ok = Disconnector.unset_trigger(local_port, remote_peer_id, ip, port)
    {:keep_state, state}
  end

  @impl :gen_statem
  def disconnecting(:cast, {:incoming_command, {_h, %Protocol.Acknowledge{}}}, state) do
    # Received an Acknowledge command in the 'disconnecting' state.
    %__MODULE__{
      worker: worker,
      connect_id: connect_id
    } = state

    send(worker, {:enet, :disconnected, :local, self(), connect_id})
    {:stop, :normal, state}
  end

  @impl :gen_statem
  def disconnecting(:cast, {:incoming_command, {_h, _c}}, state) do
    {:keep_state, state}
  end

  @impl :gen_statem
  def disconnecting(event_type, event_content, state) do
    handle_event(event_type, event_content, state)
  end

  ## terminate

  @impl :gen_statem
  def terminate(_reason, _state_name, %__MODULE__{local_port: local_port}) do
    name = get_name(self())
    Pool.disconnect_peer(local_port, name)
    :ok
  end

  ## code_change

  @impl :gen_statem
  def code_change(_old_vsn, state_name, state, _extra) do
    {:ok, state_name, state}
  end

  ## Internal functions

  defp handle_event(:cast, {:incoming_packet, from_ip, sent_time, packet}, state) do
    # Received an incoming packet of commands.
    %__MODULE__{port: port, manager_pid: manager_pid} = state
    {:ok, commands} = ProtocolDecoder.commands(packet)

    Enum.each(commands, fn
      {h = %Protocol.CommandHeader{please_acknowledge: 0}, c} ->
        # Received command that does not need to be acknowledged.
        :gen_statem.cast(self(), {:incoming_command, {h, c}})

      {h = %Protocol.CommandHeader{please_acknowledge: 1}, c} ->
        # Received a command that should be acknowledged.
        {ack_h, ack_c} = Command.acknowledge(h, sent_time)
        h_bin = ProtocolEncoder.command_header(ack_h)
        c_bin = ProtocolEncoder.command(ack_c)

        remote_peer_id =
          case c do
            %Protocol.Connect{} -> c.outgoing_peer_id
            %Protocol.VerifyConnect{} -> c.outgoing_peer_id
            _ -> state.remote_peer_id
          end

        {:sent_time, _ack_sent_time} =
          send_outgoing_commands(manager_pid, [h_bin, c_bin], from_ip, port, remote_peer_id)

        :gen_statem.cast(self(), {:incoming_command, {h, c}})
    end)

    {:keep_state, %{state | ip: from_ip}}
  end

  defp handle_event({:call, from}, :channels, state) do
    {:keep_state, state, [{:reply, from, state.channels}]}
  end

  defp handle_event({:call, from}, :pool, state) do
    {:keep_state, state, [{:reply, from, state.local_port}]}
  end

  defp handle_event({:call, from}, :pool_worker_id, state) do
    worker_id = Pool.worker_id(state.local_port, get_name(self()))
    {:keep_state, state, [{:reply, from, worker_id}]}
  end

  defp handle_event({:call, from}, {:channel, id}, state) do
    %__MODULE__{channels: channels} = state
    channel = Map.get(channels, id)
    {:keep_state, state, [{:reply, from, channel}]}
  end

  defp handle_event(:info, {:DOWN, _, :process, o, _}, %__MODULE__{worker: o} = state) do
    {:stop, :worker_process_down, state}
  end

  defp start_channels(n) do
    ids = Enum.to_list(0..(n - 1))

    channels =
      Enum.map(ids, fn id ->
        {:ok, channel} = Channel.start_link(id, self())
        {id, channel}
      end)

    Map.new(channels)
  end

  defp make_resend_timer(channel_id, sent_time, sequence_number, time, data) do
    {{:timeout, {channel_id, sent_time, sequence_number}}, time, data}
  end

  defp cancel_resend_timer(channel_id, sent_time, sequence_number) do
    {{:timeout, {channel_id, sent_time, sequence_number}}, :cancel}
  end

  defp send_outgoing_commands(manager_pid, data, ip, port) do
    send_outgoing_commands(manager_pid, data, ip, port, Constants.max_peer_id())
  end

  defp send_outgoing_commands(manager_pid, data, ip, port, peer_id) do
    # Try to determine if ManagerPid is godot_dtls_echo_server (GenServer) or enet_host (gen_server)
    # Both use gen_server:call, so we can just try it
    try do
      :gen_server.call(manager_pid, {:send_outgoing_commands, data, ip, port, peer_id}, 5000)
    catch
      :exit, {:noproc, _} ->
        Logger.error("gen_server:call failed for ManagerPid #{inspect(manager_pid)}: noproc")
        {:error, :noproc}

      :exit, {:timeout, _} ->
        Logger.error("gen_server:call failed for ManagerPid #{inspect(manager_pid)}: timeout")
        {:error, :timeout}

      class, reason ->
        Logger.error(
          "gen_server:call failed for ManagerPid #{inspect(manager_pid)}: #{inspect(class)}:#{inspect(reason)}"
        )

        {:error, {:call_failed, class, reason}}
    end
  end

  defp reset_recv_timer do
    {{:timeout, :recv}, 2 * Constants.peer_ping_interval(), :ping}
  end

  defp reset_send_timer do
    {{:timeout, :send}, Constants.peer_ping_interval(), :ping}
  end

  defp start_worker({module, fun, args}, peer_info) do
    :erlang.apply(module, fun, args ++ [peer_info])
  end

  defp start_worker(connect_fun, peer_info) when is_function(connect_fun) do
    connect_fun.(peer_info)
  end
end
