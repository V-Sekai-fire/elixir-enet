defmodule EnetCore.Command do
  @moduledoc """
  ENet command construction.
  Converted from enet_command.erl.
  """

  import Bitwise

  alias EnetCore.Commands
  alias EnetCore.Constants
  alias EnetCore.Protocol

  @spec acknowledge(Protocol.CommandHeader.t(), integer()) ::
          {Protocol.CommandHeader.t(), Protocol.Acknowledge.t()}
  def acknowledge(%Protocol.CommandHeader{} = h, sent_time) do
    {
      %Protocol.CommandHeader{
        command: Commands.command_acknowledge(),
        channel_id: h.channel_id,
        reliable_sequence_number: h.reliable_sequence_number
      },
      %Protocol.Acknowledge{
        received_reliable_sequence_number: h.reliable_sequence_number,
        received_sent_time: sent_time
      }
    }
  end

  @spec connect(
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          binary()
        ) :: {Protocol.CommandHeader.t(), Protocol.Connect.t()}
  # credo:disable-for-this-file Credo.Check.Refactor.FunctionArity
  def connect(
        outgoing_peer_id,
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
        outgoing_reliable_sequence_number,
        packet_data
      ) do
    window_size = calculate_initial_window_size(outgoing_bandwidth)

    {
      %Protocol.CommandHeader{
        command: Commands.command_connect(),
        please_acknowledge: 1,
        reliable_sequence_number: outgoing_reliable_sequence_number
      },
      %Protocol.Connect{
        outgoing_peer_id: outgoing_peer_id,
        incoming_session_id: incoming_session_id,
        outgoing_session_id: outgoing_session_id,
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
      }
    }
  end

  @spec verify_connect(
          Protocol.Connect.t(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer(),
          integer()
        ) :: {Protocol.CommandHeader.t(), Protocol.VerifyConnect.t()}
  def verify_connect(
        %Protocol.Connect{} = c,
        outgoing_peer_id,
        incoming_session_id,
        outgoing_session_id,
        host_channel_limit,
        incoming_bandwidth,
        outgoing_bandwidth,
        outgoing_reliable_sequence_number
      ) do
    window_size = calculate_window_size(incoming_bandwidth, c.window_size)
    isid = calculate_session_id(c.incoming_session_id, outgoing_session_id)
    osid = calculate_session_id(c.outgoing_session_id, incoming_session_id)

    {
      %Protocol.CommandHeader{
        command: Commands.command_verify_connect(),
        please_acknowledge: 1,
        reliable_sequence_number: outgoing_reliable_sequence_number
      },
      %Protocol.VerifyConnect{
        outgoing_peer_id: outgoing_peer_id,
        incoming_session_id: isid,
        outgoing_session_id: osid,
        mtu: clamp(c.mtu, Constants.max_mtu(), Constants.min_mtu()),
        window_size: window_size,
        channel_count: min(c.channel_count, host_channel_limit),
        incoming_bandwidth: incoming_bandwidth,
        outgoing_bandwidth: outgoing_bandwidth,
        packet_throttle_interval: c.packet_throttle_interval,
        packet_throttle_acceleration: c.packet_throttle_acceleration,
        packet_throttle_deceleration: c.packet_throttle_deceleration,
        connect_id: c.connect_id
      }
    }
  end

  @spec sequenced_disconnect() :: {Protocol.CommandHeader.t(), Protocol.Disconnect.t()}
  def sequenced_disconnect do
    {
      %Protocol.CommandHeader{
        please_acknowledge: 1,
        command: Commands.command_disconnect()
      },
      %Protocol.Disconnect{}
    }
  end

  @spec unsequenced_disconnect() :: {Protocol.CommandHeader.t(), Protocol.Disconnect.t()}
  def unsequenced_disconnect do
    {
      %Protocol.CommandHeader{
        unsequenced: 1,
        command: Commands.command_disconnect()
      },
      %Protocol.Disconnect{}
    }
  end

  @spec ping() :: {Protocol.CommandHeader.t(), Protocol.Ping.t()}
  def ping do
    {
      %Protocol.CommandHeader{
        unsequenced: 1,
        command: Commands.command_ping()
      },
      %Protocol.Ping{}
    }
  end

  @spec send_unsequenced(integer(), binary()) ::
          {Protocol.CommandHeader.t(), Protocol.Unsequenced.t()}
  def send_unsequenced(channel_id, data) do
    {
      %Protocol.CommandHeader{
        unsequenced: 1,
        command: Commands.command_send_unsequenced(),
        channel_id: channel_id
      },
      %Protocol.Unsequenced{data: data}
    }
  end

  @spec send_unreliable(integer(), integer(), binary()) ::
          {Protocol.CommandHeader.t(), Protocol.Unreliable.t()}
  def send_unreliable(channel_id, sequence_number, data) do
    {
      %Protocol.CommandHeader{
        command: Commands.command_send_unreliable(),
        channel_id: channel_id
      },
      %Protocol.Unreliable{sequence_number: sequence_number, data: data}
    }
  end

  @spec send_reliable(integer(), integer(), binary()) ::
          {Protocol.CommandHeader.t(), Protocol.Reliable.t()}
  def send_reliable(channel_id, reliable_sequence_number, data) do
    {
      %Protocol.CommandHeader{
        please_acknowledge: 1,
        command: Commands.command_send_reliable(),
        channel_id: channel_id,
        reliable_sequence_number: reliable_sequence_number
      },
      %Protocol.Reliable{data: data}
    }
  end

  ## Internal functions

  defp clamp(x, max, min) do
    max(min, min(max, x))
  end

  defp select_smallest(a, b, max, min) do
    clamp(min(a, b), max, min)
  end

  defp calculate_window_size(0, connect_window_size) do
    clamp(connect_window_size, Constants.max_window_size(), Constants.min_window_size())
  end

  defp calculate_window_size(incoming_bandwidth, connect_window_size) do
    initial_window_size =
      Constants.min_window_size() * incoming_bandwidth / Constants.peer_window_size_scale()

    select_smallest(
      initial_window_size,
      connect_window_size,
      Constants.max_window_size(),
      Constants.min_window_size()
    )
  end

  defp calculate_initial_window_size(0) do
    Constants.max_window_size()
  end

  defp calculate_initial_window_size(outgoing_bandwidth) do
    initial_window_size =
      Constants.max_window_size() * outgoing_bandwidth / Constants.peer_window_size_scale()

    clamp(initial_window_size, Constants.max_window_size(), Constants.min_window_size())
  end

  defp calculate_session_id(0xFF, peer_session_id) do
    peer_session_id
  end

  defp calculate_session_id(connect_session_id, peer_session_id) do
    initial_session_id = connect_session_id

    case initial_session_id + 1 &&& 0b11 do
      ^peer_session_id -> peer_session_id + 1 &&& 0b11
      incoming_session_id -> incoming_session_id
    end
  end
end
