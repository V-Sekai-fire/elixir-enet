defmodule Enet.PeerRecord do
  @moduledoc """
  ENet peer record structure.
  Converted from enet_peer.hrl.
  """

  defstruct [
    :handshake_flow,
    :peer_id,
    :ip,
    :port,
    :name,
    :manager_name,
    :manager_pid,
    :host,
    :channels,
    :connect_fun,
    :connect_packet_data
  ]
end
