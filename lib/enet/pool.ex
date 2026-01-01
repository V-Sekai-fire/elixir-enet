defmodule Enet.Pool do
  @moduledoc """
  ENet peer pool management.
  Converted from enet_pool.erl.
  """

  use GenServer
  require Logger

  defstruct [:port]

  ## API

  @spec start_link(integer(), pos_integer()) :: GenServer.on_start()
  def start_link(host_id, peer_limit) do
    GenServer.start_link(__MODULE__, [host_id, peer_limit], [])
  end

  @spec add_peer(integer(), term()) :: :ok | {:error, term()}
  def add_peer(port, name) do
    :gproc_pool.add_worker(port, name)
  end

  @spec pick_peer(integer(), integer()) :: pid() | false
  def pick_peer(port, peer_id) do
    :gproc_pool.pick_worker(port, peer_id)
  end

  @spec remove_peer(integer(), term()) :: :ok | {:error, term()}
  def remove_peer(port, name) do
    :gproc_pool.remove_worker(port, name)
  end

  @spec connect_peer(integer(), term()) :: :ok | {:error, term()}
  def connect_peer(port, name) do
    :gproc_pool.connect_worker(port, name)
  end

  @spec disconnect_peer(integer(), term()) :: :ok | {:error, term()}
  def disconnect_peer(port, name) do
    :gproc_pool.disconnect_worker(port, name)
  end

  @spec active_peers(integer()) :: [{term(), pid()}]
  def active_peers(port) do
    :gproc_pool.active_workers(port)
  end

  @spec worker_id(integer(), term()) :: integer() | false
  def worker_id(port, name) do
    :gproc_pool.worker_id(port, name)
  end

  ## GenServer callbacks

  @impl true
  def init([host_id, peer_limit]) do
    Process.flag(:trap_exit, true)
    true = :gproc.reg({:n, :l, {:enet_pool, host_id}})

    try do
      :gproc_pool.new(host_id, :direct, size: peer_limit, auto_size: false)
    catch
      :error, :exists -> :ok
    end

    {:ok, %__MODULE__{port: host_id}}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{port: port}) do
    :gproc_pool.force_delete(port)
    :ok
  end
end
