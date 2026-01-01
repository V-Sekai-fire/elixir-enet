defmodule Enet.ProtocolDecoder do
  @moduledoc """
  ENet protocol decoding.
  Converted from enet_protocol_decode.erl.
  """

  alias Enet.Protocol

  ## Protocol Header

  @spec protocol_header(binary()) :: {:ok, Protocol.Header.t(), binary()}
  def protocol_header(<<0::1, compressed::1, session_id::2, peer_id::12, commands::binary>>) do
    header = %Protocol.Header{
      compressed: compressed,
      session_id: session_id,
      peer_id: peer_id
    }

    {:ok, header, commands}
  end

  def protocol_header(<<1::1, compressed::1, session_id::2, peer_id::12, rest::binary>>) do
    <<sent_time::16, commands::binary>> = rest

    header = %Protocol.Header{
      compressed: compressed,
      session_id: session_id,
      peer_id: peer_id,
      sent_time: sent_time
    }

    {:ok, header, commands}
  end

  ## Commands

  @spec commands(binary()) :: {:ok, [{Protocol.CommandHeader.t(), term()}]}
  def commands(bin) do
    {:ok, commands(bin, [])}
  end

  defp commands(<<>>, acc) do
    Enum.reverse(acc)
  end

  defp commands(bin, acc) do
    {:ok, header, rest} = command_header(bin)
    {:ok, command, commands_bin} = command(header.command, rest)
    commands(commands_bin, [{header, command} | acc])
  end

  ## Command Header

  @spec command_header(binary()) :: {:ok, Protocol.CommandHeader.t(), binary()}
  def command_header(
        <<ack::1, is_unsequenced::1, command_type::6, channel_id::8, reliable_sequence_number::16,
          rest::binary>>
      ) do
    header = %Protocol.CommandHeader{
      please_acknowledge: ack,
      unsequenced: is_unsequenced,
      command: command_type,
      channel_id: channel_id,
      reliable_sequence_number: reliable_sequence_number
    }

    {:ok, header, rest}
  end

  ## Commands

  @spec command(integer(), binary()) :: {:ok, term(), binary()}
  def command(
        1,
        <<received_reliable_sequence_number::16, received_sent_time::16, rest::binary>>
      ) do
    command = %Protocol.Acknowledge{
      received_reliable_sequence_number: received_reliable_sequence_number,
      received_sent_time: received_sent_time
    }

    {:ok, command, rest}
  end

  def command(
        2,
        <<outgoing_peer_id::16, incoming_session_id::8, outgoing_session_id::8, mtu::32,
          window_size::32, channel_count::32, incoming_bandwidth::32, outgoing_bandwidth::32,
          packet_throttle_interval::32, packet_throttle_acceleration::32,
          packet_throttle_deceleration::32, connect_id::32, data::32, rest::binary>>
      ) do
    command = %Protocol.Connect{
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
      data: data
    }

    {:ok, command, rest}
  end

  def command(
        3,
        <<outgoing_peer_id::16, incoming_session_id::8, outgoing_session_id::8, mtu::32,
          window_size::32, channel_count::32, incoming_bandwidth::32, outgoing_bandwidth::32,
          packet_throttle_interval::32, packet_throttle_acceleration::32,
          packet_throttle_deceleration::32, connect_id::32, rest::binary>>
      ) do
    command = %Protocol.VerifyConnect{
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
      connect_id: connect_id
    }

    {:ok, command, rest}
  end

  def command(4, <<data::32, rest::binary>>) do
    command = %Protocol.Disconnect{data: data}
    {:ok, command, rest}
  end

  def command(5, rest) do
    command = %Protocol.Ping{}
    {:ok, command, rest}
  end

  def command(6, <<data_length::16, data_rest::binary>>) do
    <<data::binary-size(data_length), rest::binary>> = data_rest
    command = %Protocol.Reliable{data: data}
    {:ok, command, rest}
  end

  def command(
        7,
        <<sequence_number::16, data_length::16, data_rest::binary>>
      ) do
    <<data::binary-size(data_length), rest::binary>> = data_rest
    command = %Protocol.Unreliable{sequence_number: sequence_number, data: data}
    {:ok, command, rest}
  end

  def command(
        9,
        <<unsequenced_group::16, data_length::16, data_rest::binary>>
      ) do
    <<data::binary-size(data_length), rest::binary>> = data_rest
    command = %Protocol.Unsequenced{group: unsequenced_group, data: data}
    {:ok, command, rest}
  end

  def command(
        8,
        <<start_sequence_number::16, data_length::16, fragment_count::32, fragment_number::32,
          total_length::32, fragment_offset::32, data_rest::binary>>
      ) do
    <<data::binary-size(data_length), rest::binary>> = data_rest

    command = %Protocol.Fragment{
      start_sequence_number: start_sequence_number,
      fragment_count: fragment_count,
      fragment_number: fragment_number,
      total_length: total_length,
      fragment_offset: fragment_offset,
      data: data
    }

    {:ok, command, rest}
  end

  def command(
        10,
        <<incoming_bandwidth::32, outgoing_bandwidth::32, rest::binary>>
      ) do
    command = %Protocol.BandwidthLimit{
      incoming_bandwidth: incoming_bandwidth,
      outgoing_bandwidth: outgoing_bandwidth
    }

    {:ok, command, rest}
  end

  def command(
        11,
        <<packet_throttle_interval::32, packet_throttle_acceleration::32,
          packet_throttle_deceleration::32, rest::binary>>
      ) do
    command = %Protocol.ThrottleConfigure{
      packet_throttle_interval: packet_throttle_interval,
      packet_throttle_acceleration: packet_throttle_acceleration,
      packet_throttle_deceleration: packet_throttle_deceleration
    }

    {:ok, command, rest}
  end
end
