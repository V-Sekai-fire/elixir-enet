defmodule EnetCore.Supervisor do
  @moduledoc """
  ENet main supervisor.
  Converted from enet_sup.erl.
  """

  use Supervisor
  require Logger

  alias SpatialNodeStoreAPI.GodotDtlsEchoConnSup
  alias SpatialNodeStoreAPI.GodotDtlsEchoListener

  ## API

  @spec start_link() :: Supervisor.on_start()
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec start_host_supervisor(integer(), function() | mfa(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def start_host_supervisor(port, connect_fun, options) do
    child = %{
      id: port,
      start: {EnetCore.HostSupervisor, :start_link, [port, connect_fun, options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor,
      modules: [EnetCore.HostSupervisor]
    }

    Supervisor.start_child(__MODULE__, child)
  end

  @spec start_host_dtls_supervisor(integer(), function() | mfa(), keyword()) ::
          {:ok, integer()} | {:error, term()}
  def start_host_dtls_supervisor(port, connect_fun, options) do
    # Generate unique ID for this host instance (supports multiple clients on port 0)
    host_id =
      case port do
        0 -> :erlang.unique_integer([:positive, :monotonic])
        _ -> port
      end

    # Listener: the socket listener gen_server
    listener = %{
      id: {:listener, host_id},
      start: {GodotDtlsEchoListener, :start_link, [port, host_id, connect_fun, options]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker,
      modules: [GodotDtlsEchoListener]
    }

    # ConnSup: dynamic supervisor for connections
    conn_sup = %{
      id: {:connection_sup, host_id},
      start: {GodotDtlsEchoConnSup, :start_link, [host_id, connect_fun, options]},
      restart: :permanent,
      shutdown: 5000,
      type: :supervisor,
      modules: [GodotDtlsEchoConnSup]
    }

    # EnetHost: host supervisor
    enet_host = %{
      id: {:enet_host_sup, host_id},
      start: {EnetCore.HostSupervisor, :start_link, [host_id, connect_fun, options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor,
      modules: [EnetCore.HostSupervisor]
    }

    with {:ok, _} <- Supervisor.start_child(__MODULE__, listener),
         {:ok, _} <- Supervisor.start_child(__MODULE__, conn_sup),
         {:ok, _} <- Supervisor.start_child(__MODULE__, enet_host) do
      {:ok, host_id}
    else
      error -> error
    end
  end

  @spec stop_host_supervisor(integer()) :: :ok | {:error, term()}
  def stop_host_supervisor(host_sup) do
    Supervisor.terminate_child(__MODULE__, host_sup)
  end

  ## Supervisor callbacks

  @impl true
  def init(_args) do
    sup_flags = %{
      strategy: :one_for_one,
      intensity: 1,
      period: 5
    }

    {:ok, {sup_flags, []}}
  end
end
