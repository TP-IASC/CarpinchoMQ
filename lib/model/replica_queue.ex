defmodule ReplicaQueue do
  use Queue
  require Logger

  def init([name, max_size]) do
    primary = primary_name()
    initial_state = %{ elements: [], subscribers: [], max_size: max_size}
    state = if Queue.alive?(primary), do: Queue.state(primary), else: initial_state
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)
    { :ok, state }
  end

  def handle_cast({:push, message}, state) do
    { :noreply, %{ elements: [message | state.elements], subscribers: state.subscribers } }
  end

  def handle_cast({:subscribe, pid}, state) do
    { :noreply, %{ elements: state.elements, subscribers: [pid | state.subscribers] } }
  end

  def handle_cast({:unsubscribe, pid}, state) do
    { :noreply, %{ elements: state.elements, subscribers: List.delete(state.subscribers, pid) } }
  end

  defp primary_name() do
    Queue.primary_name(name())
  end
end
