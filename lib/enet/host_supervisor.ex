defmodule Enet.HostSupervisor do
  @moduledoc """
  ENet host supervisor.
  Converted from enet_host_sup.erl.
  """

  use Supervisor
  require Logger

  ## API

  @spec start_link(integer(), function() | mfa(), keyword()) :: Supervisor.on_start()
  def start_link(host_id, connect_fun, options) do
    Supervisor.start_link(__MODULE__, [host_id, connect_fun, options])
  end

  ## Supervisor callbacks

  @impl true
  def init([host_id, connect_fun, options]) do
    sup_flags = %{
      strategy: :one_for_one,
      intensity: 1,
      period: 5
    }

    peer_limit =
      case Keyword.get(options, :peer_limit) do
        nil -> 1
        limit -> limit
      end

    pool = %{
      id: Enet.Pool,
      start: {Enet.Pool, :start_link, [host_id, peer_limit]},
      restart: :permanent,
      shutdown: 2000,
      type: :worker,
      modules: [Enet.Pool]
    }

    host = %{
      id: Enet.Host,
      start: {Enet.Host, :start_link, [host_id, connect_fun, options]},
      restart: :permanent,
      shutdown: 2000,
      type: :worker,
      modules: [Enet.Host]
    }

    disconnector = %{
      id: Enet.Disconnector,
      start: {Enet.Disconnector, :start_link, [host_id]},
      restart: :permanent,
      shutdown: 1000,
      type: :worker,
      modules: [Enet.Disconnector]
    }

    peer_sup = %{
      id: Enet.PeerSupervisor,
      start: {Enet.PeerSupervisor, :start_link, [host_id]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor,
      modules: [Enet.PeerSupervisor]
    }

    {:ok, {sup_flags, [pool, host, disconnector, peer_sup]}}
  end
end
