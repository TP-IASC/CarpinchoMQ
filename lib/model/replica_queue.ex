defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(name) do
    primary = primary_name()
    initial_state = %{ elements: [], subscribers: [], work_mode: nil }
    state = if Queue.alive?(primary), do: Queue.state(primary), else: initial_state
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)
    { :ok, state }
  end

  def handle_cast({:push, message}, state) do
    { :noreply, %{ elements: [message | state.elements], subscribers: state.subscribers, work_mode: state.work_mode } }
  end

  def handle_cast({:subscribe, pid}, state) do
    { :noreply, %{ elements: state.elements, subscribers: [pid | state.subscribers], work_mode: state.work_mode } }
  end

  def handle_cast({:unsubscribe, pid}, state) do
    { :noreply, %{ elements: state.elements, subscribers: List.delete(state.subscribers, pid), work_mode: state.work_mode } }
  end

  defp primary_name() do
    Queue.primary_name(name())
  end
end
