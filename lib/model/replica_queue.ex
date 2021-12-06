defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(default_state) do
    Logger.info "Queue: #{default_state.name} started"
    Process.flag(:trap_exit, true)
    { :ok, default_state }
  end

  def handle_continue(:check_replica, default_state) do
    primary = Queue.replica_name(default_state.name)
    state = OK.try do
      primary_state <- Queue.state(primary)
    after
      primary_state |> Map.put(:name, default_state.name)
    rescue
      _ -> default_state
    end
    { :noreply, state }
  end

  def handle_cast({:push, message}, state) do
    { :noreply, Map.put(state, :elements, [%{message: message, consumers_that_did_not_ack: []}|state.elements]) }
  end

  def handle_cast({:delete, element}, state) do
    { :noreply, Map.put(state, :elements, List.delete(state.elements, element)) }
  end

  def handle_cast({:subscribe, pid}, state) do
    { :noreply, Map.put(state, :subscribers, [pid|state.subscribers]) }
  end

  def handle_cast({:unsubscribe, pid}, state) do
    { :noreply, Map.put(state, :subscribers, List.delete(state.subscribers, pid)) }
  end

  def handle_cast({:add_receivers_to_state_message, subscribers, message}, state) do
    { :noreply, Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, subscribers)
      else
        element
      end
    end)) }
  end

  def handle_cast({:send_ack, message, consumer_pid}, state) do
    { :noreply, Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, List.delete(element.consumers_that_did_not_ack, consumer_pid))
      else
        element
      end
    end)) }
  end
end
