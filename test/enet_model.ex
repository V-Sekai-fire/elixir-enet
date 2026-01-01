defmodule EnetCore.Model do
  @moduledoc """
  PropCheck state machine model for EnetCore property-based testing.
  
  This module implements the proper_statem behaviour to define a state machine
  model that mirrors the EnetCore API behavior for property-based testing.
  """

  @behaviour :proper_statem

  alias EnetCore.Peer
  alias EnetCore.Sync

  defstruct hosts: []

  # Peer struct
  defmodule PeerStruct do
    @moduledoc """
    Internal struct representing a peer connection in the state machine model.
    """
    defstruct [:connect_id, :pid, :channel_count, channels: %{}]
  end

  # Host map structure: %{port: port, peer_limit: limit, channel_limit: limit, peer_count: count, peers: [Peer]}

  @doc """
  Initial state for the state machine.
  """
  def initial_state do
    %__MODULE__{}
  end

  @doc """
  Generate a command based on the current state.
  """
  def command(%__MODULE__{hosts: []}) do
    {:call, Sync, :start_host, [connect_fun(), host_options()]}
  end

  def command(%__MODULE__{hosts: hosts} = state) do
    all_peers = Enum.flat_map(hosts, fn h -> Map.get(h, :peers, []) end)

    always_possible_commands = [
      {:call, Sync, :start_host, [connect_fun(), host_options()]},
      {:call, Sync, :stop_host, [host_port(state)]},
      connect_command(state)
    ]

    commands_needing_peers =
      if Enum.empty?(all_peers) do
        []
      else
        [
          {:call, Sync, :disconnect, [peer_pid(state), peer_pid(state)]},
          {:call, Sync, :send_unsequenced, [channel_pid(state), message_data()]},
          {:call, Sync, :send_unreliable, [channel_pid(state), message_data()]},
          {:call, Sync, :send_reliable, [channel_pid(state), message_data()]}
        ]
      end

    # Use PropEr's oneof through PropCheck
    :proper_types.oneof(always_possible_commands ++ commands_needing_peers)
  end

  defp connect_command(state) do
    # This will be evaluated by PropEr's ?LET macro
    {:call, Sync, :connect, [
      {:call, __MODULE__, :started_host_port, [state]},
      {:call, __MODULE__, :started_host_port, [state]},
      {:call, __MODULE__, :channel_count_for_hosts, [state]}
    ]}
  end

  def started_host_port(%__MODULE__{hosts: hosts}) do
    if Enum.empty?(hosts) do
      0
    else
      host = Enum.random(hosts)
      host.port
    end
  end

  def channel_count_for_hosts(%__MODULE__{hosts: hosts}) do
    if length(hosts) >= 2 do
      [h1, h2 | _] = hosts
      min(h1.channel_limit, h2.channel_limit)
    else
      1
    end
  end

  @doc """
  Check if a command can be executed in the current state.
  """
  def precondition(state, {:call, Sync, :stop_host, [port]}) do
    get_host_with_port(state, port) != nil
  end

  def precondition(state, {:call, _, :connect_from_full_local_host, [l_port, _r_port, _cc]}) do
    case get_host_with_port(state, l_port) do
      nil -> false
      host -> host.peer_limit == host.peer_count
    end
  end

  def precondition(state, {:call, _, :connect_to_full_remote_host, [l_port, r_port, _cc]}) do
    local_host = get_host_with_port(state, l_port)
    remote_host = get_host_with_port(state, r_port)

    case {local_host, remote_host} do
      {nil, _} -> false
      {_, nil} -> false
      {l, r} -> l.peer_limit > l.peer_count && r.peer_limit == r.peer_count
    end
  end

  def precondition(_state, {:call, _, :connect_to_self, [l_port, r_port, _cc]}) do
    l_port == r_port
  end

  def precondition(state, {:call, Sync, :connect, [l_port, r_port, _channel_count]}) do
    local_host = get_host_with_port(state, l_port)
    remote_host = get_host_with_port(state, r_port)

    case {local_host, remote_host} do
      {nil, _} -> false
      {_, nil} -> false
      {l, r} -> l.peer_limit > l.peer_count && r.peer_limit > r.peer_count
    end
  end

  def precondition(_state, _command) do
    true
  end

  @doc """
  Update state after executing a command.
  """
  def next_state(state, {:ok, port}, {:call, Sync, :start_host, [_connect_fun, options]}) do
    peer_limit = Keyword.get(options, :peer_limit)
    channel_limit = Keyword.get(options, :channel_limit)

    new_host = %{
      port: port,
      peer_limit: peer_limit,
      channel_limit: channel_limit,
      peer_count: 0,
      peers: []
    }

    %{state | hosts: [new_host | state.hosts]}
  end

  def next_state(state, _result, {:call, Sync, :stop_host, [port]}) do
    host = Enum.find(state.hosts, fn h -> h.port == port end)
    connect_ids = Enum.map(Map.get(host, :peers, []), fn p -> p.connect_id end)

    updated_hosts =
      Enum.map(state.hosts, fn h ->
        update_host_after_stop(h, port, connect_ids)
      end)
      |> Enum.reject(&is_nil/1)

    %{state | hosts: updated_hosts}
  end

  defp update_host_after_stop(h, port, connect_ids) do
    if h.port == port do
      nil
    else
      peers =
        Enum.filter(Map.get(h, :peers, []), fn p ->
          p.connect_id not in connect_ids
        end)

      %{h | peer_count: length(peers), peers: peers}
    end
  end

  def next_state(state, _result, {:call, _, :connect_from_full_local_host, [_l, _r, _cc]}) do
    # Trying to connect from a full host -> peer_limit_reached, state unchanged
    state
  end

  def next_state(state, _result, {:call, _, :connect_to_full_remote_host, [_l, _r, _cc]}) do
    # Trying to connect to a full remote host -> timeout, state unchanged
    state
  end

  def next_state(state, result, {:call, _, :connect_to_self, [port, port, channel_count]}) do
    host = get_host_with_port(state, port)

    if host.peer_limit - host.peer_count < 2 do
      # Not enough room for two peers
      state
    else
      {l_pid, l_channels, r_pid, r_channels} = result
      connect_id = Peer.get_connect_id(l_pid)

      peer1 = %PeerStruct{
        connect_id: connect_id,
        pid: l_pid,
        channel_count: channel_count,
        channels: l_channels
      }

      peer2 = %PeerStruct{
        connect_id: connect_id,
        pid: r_pid,
        channel_count: channel_count,
        channels: r_channels
      }

      updated_host = %{
        host
        | peer_count: host.peer_count + 2,
          peers: [peer1, peer2 | Map.get(host, :peers, [])]
      }

      updated_hosts = replace_host_with_same_port(updated_host, state.hosts)
      %{state | hosts: updated_hosts}
    end
  end

  def next_state(state, result, {:call, Sync, :connect, [l_port, r_port, channel_count]}) do
    h1 = get_host_with_port(state, l_port)
    h2 = get_host_with_port(state, r_port)

    if h1 != nil && h2 != nil do
      {l_pid, l_channels, r_pid, r_channels} = result
      connect_id = Peer.get_connect_id(l_pid)

      peer1 = %PeerStruct{
        connect_id: connect_id,
        pid: l_pid,
        channel_count: channel_count,
        channels: l_channels
      }

      peer2 = %PeerStruct{
        connect_id: connect_id,
        pid: r_pid,
        channel_count: channel_count,
        channels: r_channels
      }

      new_h1 = %{
        h1
        | peer_count: h1.peer_count + 1,
          peers: [peer1 | Map.get(h1, :peers, [])]
      }

      new_h2 = %{
        h2
        | peer_count: h2.peer_count + 1,
          peers: [peer2 | Map.get(h2, :peers, [])]
      }

      hosts1 = replace_host_with_same_port(new_h1, state.hosts)
      hosts2 = replace_host_with_same_port(new_h2, hosts1)
      %{state | hosts: hosts2}
    else
      state
    end
  end

  def next_state(state, _result, {:call, Sync, :disconnect, [l_pid, _r_pid]}) do
    # Find connect_id for this peer
    connect_id = find_connect_id_by_pid(state, l_pid)

    updated_hosts =
      Enum.map(state.hosts, fn h ->
        peers =
          Enum.filter(Map.get(h, :peers, []), fn p ->
            p.connect_id != connect_id
          end)

        %{h | peer_count: length(peers), peers: peers}
      end)

    %{state | hosts: updated_hosts}
  end

  defp find_connect_id_by_pid(state, pid) do
    Enum.find_value(state.hosts, fn host ->
      find_peer_connect_id(host, pid)
    end)
  end

  defp find_peer_connect_id(host, pid) do
    Enum.find_value(Map.get(host, :peers, []), fn peer ->
      if peer.pid == pid, do: peer.connect_id
    end)
  end

  def next_state(state, _result, {:call, _, :send_unsequenced, [_channel_pid, _data]}) do
    state
  end

  def next_state(state, _result, {:call, _, :send_unreliable, [_channel_pid, _data]}) do
    state
  end

  def next_state(state, _result, {:call, _, :send_reliable, [_channel_pid, _data]}) do
    state
  end

  @doc """
  Check if command result is valid.
  """
  def postcondition(_state, {:call, Sync, :start_host, [_connect_fun, _opts]}, result) do
    case result do
      {:error, _reason} -> false
      {:ok, _port} -> true
    end
  end

  def postcondition(state, {:call, Sync, :stop_host, [port]}, result) do
    host_exists = Enum.any?(state.hosts, fn h -> h.port == port end)

    if host_exists do
      result == :ok
    else
      result == {:error, :not_found}
    end
  end

  def postcondition(_state, {:call, _, :connect_from_full_local_host, [_l, _r, _c]}, result) do
    result == {:error, :reached_peer_limit}
  end

  def postcondition(_state, {:call, _, :connect_to_full_remote_host, [_l, _r, _c]}, result) do
    result == {:error, :local_timeout}
  end

  def postcondition(state, {:call, _, :connect_to_self, [port, port, _c]}, result) do
    host = get_host_with_port(state, port)

    cond do
      host.peer_limit == host.peer_count ->
        result == {:error, :reached_peer_limit}

      host.peer_limit - host.peer_count == 1 ->
        result in [{:error, :local_timeout}, {:error, :reached_peer_limit}]

      true ->
        case result do
          {_l_pid, _l_channels, _r_pid, _r_channels} -> true
          {:error, _reason} -> false
        end
    end
  end

  def postcondition(state, {:call, Sync, :connect, [l_port, r_port, _c]}, result) do
    h1 = get_host_with_port(state, l_port)
    h2 = get_host_with_port(state, r_port)

    if h1 != nil && h2 != nil do
      case result do
        {_l_pid, _l_channels, _r_pid, _r_channels} -> true
        {:error, _reason} -> false
      end
    else
      false
    end
  end

  def postcondition(_state, {:call, Sync, :disconnect, [_l_peer, _r_peer]}, result) do
    result == :ok
  end

  def postcondition(_state, {:call, _, :send_unsequenced, [_channel, _data]}, result) do
    result == :ok
  end

  def postcondition(_state, {:call, _, :send_unreliable, [_channel, _data]}, result) do
    result == :ok
  end

  def postcondition(_state, {:call, _, :send_reliable, [_channel, _data]}, result) do
    result == :ok
  end

  # Generators - these need to return PropEr generators

  defp connect_fun do
    :proper_types.oneof([
      {:call, __MODULE__, :mock_connect_fun, []},
      {__MODULE__, :mock_start_worker, [{:call, Process, :self, []}]}
    ])
  end

  def mock_connect_fun do
    self = self()

    fn peer_info ->
      send(self, peer_info)
      {:ok, self}
    end
  end

  def mock_start_worker(self, peer_info) do
    send(self, peer_info)
    {:ok, self}
  end

  defp host_options do
    # Return a PropEr generator for host options
    :proper_types.let(
      [
        peer_limit <- :proper_types.integer(1, 255),
        channel_limit <- :proper_types.integer(1, 8)
      ],
      [peer_limit: peer_limit, channel_limit: channel_limit]
    )
  end

  defp host_port(%__MODULE__{hosts: hosts}) do
    if Enum.empty?(hosts) do
      0
    else
      ports = Enum.map(hosts, fn h -> h.port end)
      :proper_types.elements(ports)
    end
  end

  defp peer_pid(%__MODULE__{hosts: hosts}) do
    all_peers = Enum.flat_map(hosts, fn h -> Map.get(h, :peers, []) end)

    if Enum.empty?(all_peers) do
      nil
    else
      pids = Enum.map(all_peers, fn p -> p.pid end)
      :proper_types.elements(pids)
    end
  end

  defp channel_pid(%__MODULE__{hosts: hosts}) do
    hosts_with_peers =
      Enum.filter(hosts, fn h ->
        not Enum.empty?(Map.get(h, :peers, []))
      end)

    if Enum.empty?(hosts_with_peers) do
      nil
    else
      # This is complex - we need to generate a channel from a peer
      # For now, return a simple generator
      :proper_types.binary()
    end
  end

  defp message_data do
    :proper_types.binary()
  end

  # Helper functions

  defp get_host_with_port(%__MODULE__{hosts: hosts}, port) do
    Enum.find(hosts, fn h -> h.port == port end)
  end

  defp replace_host_with_same_port(new_host, hosts) do
    Enum.map(hosts, fn h ->
      if h.port == new_host.port, do: new_host, else: h
    end)
  end
end
