defmodule Enet.Disconnector do
  @moduledoc """
  ENet peer disconnection management.
  Converted from enet_disconnector.erl.
  """

  use GenServer
  require Logger

  alias Enet.Command
  alias Enet.Host
  alias Enet.ProtocolEncoder

  defstruct [:port]

  ## API

  @spec start_link(integer()) :: GenServer.on_start()
  def start_link(host_id) do
    GenServer.start_link(__MODULE__, [host_id], [])
  end

  @spec set_trigger(integer(), integer(), String.t(), integer()) :: :ok
  def set_trigger(host_id, peer_id, ip, port) do
    server = :gproc.where({:n, :l, {:enet_disconnector, host_id}})
    GenServer.cast(server, {:set_trigger, self(), peer_id, ip, port})
  end

  @spec unset_trigger(integer(), integer(), String.t(), integer()) :: :ok
  def unset_trigger(host_id, peer_id, ip, port) do
    server = :gproc.where({:n, :l, {:enet_disconnector, host_id}})
    GenServer.call(server, {:unset_trigger, peer_id, ip, port})
  end

  ## GenServer callbacks

  @impl true
  def init([host_id]) do
    true = :gproc.reg({:n, :l, {:enet_disconnector, host_id}})
    {:ok, %__MODULE__{port: host_id}}
  end

  @impl true
  def handle_call({:unset_trigger, peer_id, ip, port}, {peer_pid, _}, state) do
    key = {:n, :l, {peer_id, ip, port}}
    ref = :gproc.get_value(key, peer_pid)
    :ok = :gproc.demonitor(key, ref)
    true = :gproc.unreg_other(key, peer_pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:set_trigger, peer_pid, peer_id, ip, port}, state) do
    key = {:n, :l, {peer_id, ip, port}}
    true = :gproc.reg_other(key, peer_pid)
    ref = :gproc.monitor(key)
    :updated = :gproc.ensure_reg_other(key, peer_pid, ref)
    {:noreply, state}
  end

  @impl true
  def handle_info({:gproc, :unreg, _ref, {:n, :l, {peer_id, ip, port}}}, state) do
    %__MODULE__{port: host_id} = state
    {ch, command} = Command.unsequenced_disconnect()
    h_bin = ProtocolEncoder.command_header(ch)
    c_bin = ProtocolEncoder.command(command)
    data = [h_bin, c_bin]
    host = :gproc.where({:n, :l, {:enet_host, host_id}})
    Host.send_outgoing_commands(host, data, ip, port, peer_id)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
