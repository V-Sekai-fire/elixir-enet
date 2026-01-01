defmodule EnetCore.Commands do
  @moduledoc """
  ENet command type constants.
  Converted from enet_commands.hrl.
  """

  @command_acknowledge 1
  @command_connect 2
  @command_verify_connect 3
  @command_disconnect 4
  @command_ping 5
  @command_send_reliable 6
  @command_send_unreliable 7
  @command_send_fragment 8
  @command_send_unsequenced 9
  @command_bandwidth_limit 10
  @command_throttle_configure 11
  @command_send_unreliable_fragment 12

  def command_acknowledge, do: @command_acknowledge
  def command_connect, do: @command_connect
  def command_verify_connect, do: @command_verify_connect
  def command_disconnect, do: @command_disconnect
  def command_ping, do: @command_ping
  def command_send_reliable, do: @command_send_reliable
  def command_send_unreliable, do: @command_send_unreliable
  def command_send_fragment, do: @command_send_fragment
  def command_send_unsequenced, do: @command_send_unsequenced
  def command_bandwidth_limit, do: @command_bandwidth_limit
  def command_throttle_configure, do: @command_throttle_configure
  def command_send_unreliable_fragment, do: @command_send_unreliable_fragment
end
