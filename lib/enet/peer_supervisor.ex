defmodule Enet.PeerSupervisor do
  @moduledoc """
  ENet peer supervisor.
  Converted from enet_peer_sup.erl.
  """

  use Supervisor
  require Logger

  ## API

  @spec start_link(integer()) :: Supervisor.on_start()
  def start_link(host_id) do
    Supervisor.start_link(__MODULE__, [host_id])
  end

  @spec start_peer(Supervisor.supervisor(), Enet.PeerRecord.t()) ::
          {:ok, pid()} | {:error, term()}
  def start_peer(supervisor, peer) do
    Supervisor.start_child(supervisor, [peer])
  end

  ## Supervisor callbacks

  @impl true
  def init([host_id]) do
    true = :gproc.reg({:n, :l, {:enet_peer_sup, host_id}})

    sup_flags = %{
      strategy: :simple_one_for_one,
      intensity: 1,
      period: 3
    }

    child_specs = [
      %{
        id: Enet.Peer,
        start: {Enet.Peer, :start_link, [host_id]},
        restart: :temporary,
        shutdown: :brutal_kill,
        type: :worker,
        modules: [Enet.Peer]
      }
    ]

    {:ok, {sup_flags, child_specs}}
  end
end
