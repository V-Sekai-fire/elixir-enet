defmodule EnetCore.ProtocolEncoder do
  @moduledoc """
  ENet protocol encoding.
  Converted from enet_protocol_encode.erl.
  """

  alias EnetCore.Constants
  alias EnetCore.Protocol

  ## Protocol Header

  @spec protocol_header(Protocol.Header.t()) :: binary()
  def protocol_header(%Protocol.Header{sent_time: nil} = ph) do
    peer_id = ph.peer_id || Constants.max_peer_id()
    <<0::1, ph.compressed::1, ph.session_id::2, peer_id::12, <<>>::binary>>
  end

  def protocol_header(%Protocol.Header{sent_time: sent_time} = ph) do
    peer_id = ph.peer_id || Constants.max_peer_id()
    <<1::1, ph.compressed::1, ph.session_id::2, peer_id::12, sent_time::16>>
  end

  ## Command Header

  @spec command_header(Protocol.CommandHeader.t()) :: binary()
  def command_header(%Protocol.CommandHeader{} = ch) do
    <<ch.please_acknowledge::1, ch.unsequenced::1, ch.command::6, ch.channel_id::8,
      ch.reliable_sequence_number::16, <<>>::binary>>
  end

  ## Commands

  @spec command(
          Protocol.Acknowledge.t()
          | Protocol.Connect.t()
          | Protocol.VerifyConnect.t()
          | Protocol.Disconnect.t()
          | Protocol.Ping.t()
          | Protocol.Reliable.t()
          | Protocol.Unreliable.t()
          | Protocol.Unsequenced.t()
          | Protocol.Fragment.t()
          | Protocol.BandwidthLimit.t()
          | Protocol.ThrottleConfigure.t()
        ) :: binary()
  def command(%Protocol.Acknowledge{} = c) do
    <<c.received_reliable_sequence_number::16, c.received_sent_time::16, <<>>::binary>>
  end

  def command(%Protocol.Connect{} = c) do
    data_size = if is_binary(c.data), do: byte_size(c.data), else: 0

    <<c.outgoing_peer_id::16, c.incoming_session_id::8, c.outgoing_session_id::8, c.mtu::32,
      c.window_size::32, c.channel_count::32, c.incoming_bandwidth::32, c.outgoing_bandwidth::32,
      c.packet_throttle_interval::32, c.packet_throttle_acceleration::32,
      c.packet_throttle_deceleration::32, c.connect_id::32, data_size::32, <<>>::binary>>
  end

  def command(%Protocol.VerifyConnect{} = c) do
    <<c.outgoing_peer_id::16, c.incoming_session_id::8, c.outgoing_session_id::8, c.mtu::32,
      c.window_size::32, c.channel_count::32, c.incoming_bandwidth::32, c.outgoing_bandwidth::32,
      c.packet_throttle_interval::32, c.packet_throttle_acceleration::32,
      c.packet_throttle_deceleration::32, c.connect_id::32, <<>>::binary>>
  end

  def command(%Protocol.Disconnect{} = c) do
    <<c.data::32, <<>>::binary>>
  end

  def command(%Protocol.Ping{}) do
    <<>>
  end

  def command(%Protocol.Reliable{} = c) do
    data_size = iolist_size(c.data)
    <<data_size::16, c.data::binary>>
  end

  def command(%Protocol.Unreliable{} = c) do
    data_size = iolist_size(c.data)
    <<c.sequence_number::16, data_size::16, c.data::binary>>
  end

  def command(%Protocol.Unsequenced{} = c) do
    data_size = iolist_size(c.data)
    <<c.group::16, data_size::16, c.data::binary>>
  end

  def command(%Protocol.Fragment{} = c) do
    data_size = iolist_size(c.data)

    <<c.start_sequence_number::16, data_size::16, c.fragment_count::32, c.fragment_number::32,
      c.total_length::32, c.fragment_offset::32, c.data::binary>>
  end

  def command(%Protocol.BandwidthLimit{} = c) do
    <<c.incoming_bandwidth::32, c.outgoing_bandwidth::32, <<>>::binary>>
  end

  def command(%Protocol.ThrottleConfigure{} = c) do
    <<c.packet_throttle_interval::32, c.packet_throttle_acceleration::32,
      c.packet_throttle_deceleration::32, <<>>::binary>>
  end

  # Helper for iolist_size
  defp iolist_size(data) when is_binary(data), do: byte_size(data)
  defp iolist_size(data) when is_list(data), do: :erlang.iolist_size(data)
  defp iolist_size(_), do: 0
end
