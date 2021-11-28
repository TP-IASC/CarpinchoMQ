defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(default_state) do
    Logger.info "Queue: #{default_state.name} started"
    Process.flag(:trap_exit, true)
    { :ok, default_state }
  end

  def handle_continue(:check_replica, default_state) do
    primary = Queue.primary_name(default_state.name)
    state = if Queue.alive?(primary), do: Queue.state(primary) |> Map.put(:name, default_state.name), else: default_state
    { :noreply, state }
  end

  def handle_cast({:push, message}, state) do
    { :noreply, Map.put(state, :elements, [message|state.elements]) }
  end

  def handle_cast({:delete, message}, state) do
    { :noreply, Map.put(state, :elements, List.delete(state.elements, message)) }
  end

  def handle_cast({:subscribe, pid}, state) do
    { :noreply, Map.put(state, :subscribers, [pid|state.subscribers]) }
  end

  def handle_cast({:unsubscribe, pid}, state) do
    { :noreply, Map.put(state, :subscribers, List.delete(state.subscribers, pid)) }
  end
end
