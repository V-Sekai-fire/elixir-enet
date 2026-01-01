defmodule Enet.Constants do
  @moduledoc """
  ENet protocol constants.
  Converted from enet_constants.hrl.
  """

  import Bitwise

  # Limits
  @min_mtu 576
  @max_mtu 4096
  @max_packet_commands 32
  @min_window_size 4096
  @max_window_size 65_536
  @min_channel_count 1
  @max_channel_count 255
  @max_peer_id 0xFFF
  @max_fragment_count 1_048_575

  # Defaults
  @host_receive_buffer_size 256 * 1024
  @host_send_buffer_size 256 * 1024
  @host_bandwidth_throttle_interval 1000
  @host_default_mtu 1392
  @host_default_maximum_packet_size 32 * 1024 * 1024
  @host_default_maximum_waiting_data 32 * 1024 * 1024

  @peer_default_round_trip_time 500
  @peer_default_packet_throttle 32
  @peer_packet_throttle_scale 32
  @peer_packet_throttle_counter 7
  @peer_packet_throttle_acceleration 2
  @peer_packet_throttle_deceleration 2
  @peer_packet_throttle_interval 5000
  @peer_packet_loss_scale bsl(1, 16)
  @peer_packet_loss_interval 10_000
  @peer_window_size_scale 64 * 1024
  @peer_timeout_limit 32
  @peer_timeout_minimum 5000
  @peer_timeout_maximum 30_000
  @peer_ping_interval 500
  @peer_unsequenced_windows 64
  @peer_unsequenced_window_size 1024
  @peer_free_unsequenced_windows 32
  @peer_reliable_windows 16
  @peer_reliable_window_size 0x1000
  @peer_free_reliable_windows 8

  # Getters
  def min_mtu, do: @min_mtu
  def max_mtu, do: @max_mtu
  def max_packet_commands, do: @max_packet_commands
  def min_window_size, do: @min_window_size
  def max_window_size, do: @max_window_size
  def min_channel_count, do: @min_channel_count
  def max_channel_count, do: @max_channel_count
  def max_peer_id, do: @max_peer_id
  def max_fragment_count, do: @max_fragment_count

  def host_receive_buffer_size, do: @host_receive_buffer_size
  def host_send_buffer_size, do: @host_send_buffer_size
  def host_bandwidth_throttle_interval, do: @host_bandwidth_throttle_interval
  def host_default_mtu, do: @host_default_mtu
  def host_default_maximum_packet_size, do: @host_default_maximum_packet_size
  def host_default_maximum_waiting_data, do: @host_default_maximum_waiting_data

  def peer_default_round_trip_time, do: @peer_default_round_trip_time
  def peer_default_packet_throttle, do: @peer_default_packet_throttle
  def peer_packet_throttle_scale, do: @peer_packet_throttle_scale
  def peer_packet_throttle_counter, do: @peer_packet_throttle_counter
  def peer_packet_throttle_acceleration, do: @peer_packet_throttle_acceleration
  def peer_packet_throttle_deceleration, do: @peer_packet_throttle_deceleration
  def peer_packet_throttle_interval, do: @peer_packet_throttle_interval
  def peer_packet_loss_scale, do: @peer_packet_loss_scale
  def peer_packet_loss_interval, do: @peer_packet_loss_interval
  def peer_window_size_scale, do: @peer_window_size_scale
  def peer_timeout_limit, do: @peer_timeout_limit
  def peer_timeout_minimum, do: @peer_timeout_minimum
  def peer_timeout_maximum, do: @peer_timeout_maximum
  def peer_ping_interval, do: @peer_ping_interval
  def peer_unsequenced_windows, do: @peer_unsequenced_windows
  def peer_unsequenced_window_size, do: @peer_unsequenced_window_size
  def peer_free_unsequenced_windows, do: @peer_free_unsequenced_windows
  def peer_reliable_windows, do: @peer_reliable_windows
  def peer_reliable_window_size, do: @peer_reliable_window_size
  def peer_free_reliable_windows, do: @peer_free_reliable_windows
end
