defmodule Enet.Application do
  @moduledoc """
  ENet core application.
  Converted from enet_app.erl.
  """

  use Application

  @impl true
  def start(_type, _args) do
    case Enet.Supervisor.start_link() do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def stop(_state) do
    :ok
  end
end
