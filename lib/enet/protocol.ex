defmodule Enet.Protocol do
  @moduledoc """
  ENet protocol record definitions.
  Converted from enet_protocol.hrl.
  """

  defstruct [
    :compressed,
    :session_id,
    :peer_id,
    :sent_time,
    :checksum
  ]

  defmodule Header do
    @moduledoc """
    Protocol header structure.
    """
    defstruct compressed: 0,
              session_id: 0,
              peer_id: nil,
              sent_time: nil,
              checksum: nil

    def default_peer_id do
      Constants.max_peer_id()
    end
  end

  defmodule CommandHeader do
    @moduledoc """
    Command header structure.
    """
    defstruct please_acknowledge: 0,
              unsequenced: 0,
              command: 0,
              channel_id: 0xFF,
              reliable_sequence_number: 0
  end

  defmodule Acknowledge do
    @moduledoc """
    Acknowledge command structure.
    """
    defstruct received_reliable_sequence_number: 0,
              received_sent_time: 0
  end

  defmodule Connect do
    @moduledoc """
    Connect command structure.
    """
    defstruct outgoing_peer_id: 0,
              incoming_session_id: 0,
              outgoing_session_id: 0,
              mtu: nil,
              window_size: nil,
              channel_count: nil,
              incoming_bandwidth: 0,
              outgoing_bandwidth: 0,
              packet_throttle_interval: 0,
              packet_throttle_acceleration: 0,
              packet_throttle_deceleration: 0,
              connect_id: 0,
              data: 0
  end

  defmodule VerifyConnect do
    @moduledoc """
    Verify connect command structure.
    """
    defstruct outgoing_peer_id: 0,
              incoming_session_id: 0,
              outgoing_session_id: 0,
              mtu: nil,
              window_size: nil,
              channel_count: nil,
              incoming_bandwidth: 0,
              outgoing_bandwidth: 0,
              packet_throttle_interval: 0,
              packet_throttle_acceleration: 0,
              packet_throttle_deceleration: 0,
              connect_id: 0
  end

  defmodule Disconnect do
    @moduledoc """
    Disconnect command structure.
    """
    defstruct data: 0
  end

  defmodule Ping do
    @moduledoc """
    Ping command structure.
    """
    defstruct []
  end

  defmodule Reliable do
    @moduledoc """
    Reliable command structure.
    """
    defstruct data: <<>>
  end

  defmodule Unreliable do
    @moduledoc """
    Unreliable command structure.
    """
    defstruct sequence_number: 0,
              data: <<>>
  end

  defmodule Unsequenced do
    @moduledoc """
    Unsequenced command structure.
    """
    defstruct group: 0,
              data: <<>>
  end

  defmodule Fragment do
    @moduledoc """
    Fragment command structure.
    """
    defstruct start_sequence_number: 0,
              fragment_count: 0,
              fragment_number: 0,
              total_length: 0,
              fragment_offset: 0,
              data: <<>>
  end

  defmodule BandwidthLimit do
    @moduledoc """
    Bandwidth limit command structure.
    """
    defstruct incoming_bandwidth: 0,
              outgoing_bandwidth: 0
  end

  defmodule ThrottleConfigure do
    @moduledoc """
    Throttle configure command structure.
    """
    defstruct packet_throttle_interval: 0,
              packet_throttle_acceleration: 0,
              packet_throttle_deceleration: 0
  end
end
