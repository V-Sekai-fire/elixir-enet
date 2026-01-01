defmodule EnetCore.Channel do
  @moduledoc """
  ENet channel gen_server.
  Converted from enet_channel_srv.erl.
  """

  use GenServer
  require Logger

  alias EnetCore.Command
  alias EnetCore.Peer
  alias EnetCore.Protocol

  @enet_max_seq_index 65_536
  @enet_peer_reliable_window_size 0x1000

  defstruct [
    :id,
    :peer,
    :worker,
    :sys_parent,
    :sys_debug,
    incoming_reliable_sequence_number: 1,
    incoming_unreliable_sequence_number: 1,
    outgoing_reliable_sequence_number: 1,
    outgoing_unreliable_sequence_number: 1,
    reliable_window: []
  ]

  ## API

  @spec start_link(term(), term()) :: GenServer.on_start()
  def start_link(id, peer) do
    GenServer.start_link(__MODULE__, [id, peer], [])
  end

  @spec stop(pid()) :: :ok
  def stop(channel) do
    GenServer.stop(channel)
  end

  @spec set_worker(pid(), pid()) :: :ok
  def set_worker(channel, worker) do
    GenServer.cast(channel, {:set_worker, worker})
  end

  @spec recv_unsequenced(pid(), {Protocol.CommandHeader.t(), Protocol.Unsequenced.t()}) :: :ok
  def recv_unsequenced(channel, {h, c}) do
    GenServer.cast(channel, {:recv_unsequenced, {h, c}})
  end

  @spec send_unsequenced(pid(), iodata()) :: :ok
  def send_unsequenced(channel, data) do
    GenServer.cast(channel, {:send_unsequenced, data})
  end

  @spec recv_unreliable(pid(), {Protocol.CommandHeader.t(), Protocol.Unreliable.t()}) :: :ok
  def recv_unreliable(channel, {h, c}) do
    GenServer.cast(channel, {:recv_unreliable, {h, c}})
  end

  @spec send_unreliable(pid(), iodata()) :: :ok
  def send_unreliable(channel, data) do
    GenServer.cast(channel, {:send_unreliable, data})
  end

  @spec recv_reliable(pid(), {Protocol.CommandHeader.t(), Protocol.Reliable.t()}) :: :ok
  def recv_reliable(channel, {h, c}) do
    GenServer.cast(channel, {:recv_reliable, {h, c}})
  end

  @spec send_reliable(pid(), iodata()) :: :ok
  def send_reliable(channel, data) do
    GenServer.cast(channel, {:send_reliable, data})
  end

  ## GenServer callbacks

  @impl true
  def init([id, peer]) do
    {:ok, %__MODULE__{id: id, peer: peer}}
  end

  @impl true
  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:set_worker, worker}, state) do
    {:noreply, %{state | worker: worker}}
  end

  @impl true
  def handle_cast(
        {:recv_unsequenced, {%Protocol.CommandHeader{unsequenced: 1}, %Protocol.Unsequenced{} = c}},
        state
      ) do
    %__MODULE__{worker: worker, id: id} = state
    data = c.data
    send(worker, {:enet, id, data})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_unsequenced, data}, state) do
    %__MODULE__{id: id, peer: peer} = state
    {h, c} = Command.send_unsequenced(id, data)
    :ok = Peer.send_command(peer, {h, c})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:recv_unreliable, {_h, %Protocol.Unreliable{sequence_number: n} = c}}, state) do
    expected = state.incoming_unreliable_sequence_number

    if n < expected or n - expected >= @enet_max_seq_index / 2 do
      # Data is old - drop it and continue.
      Logger.debug("Discard outdated packet. Recv: #{n}. Expect: #{expected}")
      {:noreply, state}
    else
      # N is equal to or greater than the expected packet. Dispatch it.
      %__MODULE__{worker: worker, id: id} = state
      data = c.data
      send(worker, {:enet, id, data})
      next_seq = maybe_wrap(n + 1)
      {:noreply, %{state | incoming_unreliable_sequence_number: next_seq}}
    end
  end

  @impl true
  def handle_cast({:send_unreliable, data}, state) do
    %__MODULE__{id: id, peer: peer} = state
    n = state.outgoing_unreliable_sequence_number
    {h, c} = Command.send_unreliable(id, n, data)
    :ok = Peer.send_command(peer, {h, c})
    new_state = %{state | outgoing_unreliable_sequence_number: maybe_wrap(n + 1)}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:recv_reliable, _data}, state)
      when length(state.reliable_window) > @enet_peer_reliable_window_size do
    {:stop, :out_of_sync, state}
  end

  @impl true
  def handle_cast(
        {:recv_reliable,
         {%Protocol.CommandHeader{reliable_sequence_number: n}, %Protocol.Reliable{} = c}},
        state
      ) do
    expected = state.incoming_reliable_sequence_number

    cond do
      n > expected or n - expected <= -@enet_max_seq_index / 2 ->
        Logger.debug("Buffer ahead-of-sequence packet. Recv: #{n}. Expect: #{expected}.")
        reliable_window0 = state.reliable_window
        {:noreply, %{state | reliable_window: [{n, c} | reliable_window0]}}

      n < expected or n - expected >= @enet_max_seq_index / 2 ->
        Logger.debug("Discard outdated packet. Recv: #{n}. Expect: #{expected}")
        {:noreply, state}

      true ->
        # Must be equal, and so dispatch:
        %__MODULE__{id: id, worker: worker} = state
        # Dispatch this packet
        data = c.data
        send(worker, {:enet, id, data})
        # Dispatch any buffered packets
        window = state.reliable_window
        sorted_window = wrapped_sort(window)
        {next_seq, new_window} = dispatch(n, sorted_window, id, worker)

        {:noreply,
         %{state | incoming_reliable_sequence_number: next_seq, reliable_window: new_window}}
    end
  end

  @impl true
  def handle_cast({:send_reliable, data}, state) do
    %__MODULE__{id: id, peer: peer} = state
    n = state.outgoing_reliable_sequence_number
    {h, c} = Command.send_reliable(id, n, data)
    :ok = Peer.send_command(peer, {h, c})
    new_state = %{state | outgoing_reliable_sequence_number: maybe_wrap(n + 1)}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    Logger.debug("Current state: #{inspect(state)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Got unhandled msg: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  ## Internal functions

  @spec dispatch(pos_integer(), list(), pos_integer(), pid()) :: {pos_integer(), list()}
  defp dispatch(cur_seq, [], _channel_id, _worker) do
    next_seq = maybe_wrap(cur_seq + 1)
    {next_seq, []}
  end

  defp dispatch(cur_seq, [{seq1, d1} | remaining_window] = window, channel_id, worker) do
    # If the buffered item comes immediately after the current sequence number,
    # dispatch the next packet.
    next_seq = maybe_wrap(cur_seq + 1)

    if next_seq == seq1 do
      # Dispatch the packet
      Logger.debug("Dispatching queued packet #{seq1}")

      # Extract data from command record before sending to worker
      data =
        case d1 do
          %Protocol.Reliable{} -> d1.data
          %Protocol.Unreliable{} -> d1.data
          %Protocol.Unsequenced{} -> d1.data
          _ -> d1
        end

      send(worker, {:enet, channel_id, data})
      dispatch(next_seq, remaining_window, channel_id, worker)
    else
      # The first packet in the window is not the one we're looking for,
      # so just return.
      {next_seq, window}
    end
  end

  defp maybe_wrap(seq) do
    # Must wrap at 16-bits.
    rem(seq, @enet_max_seq_index)
  end

  defp wrapped_sort(list) do
    # Keysort while preserving order through 16-bit integer wrapping.
    f = fn {a, _}, {b, _} ->
      compare = b - a

      cond do
        compare > 0 and compare <= @enet_max_seq_index / 2 -> true
        compare < 0 and compare <= -@enet_max_seq_index / 2 -> true
        true -> false
      end
    end

    Enum.sort(list, f)
  end
end
