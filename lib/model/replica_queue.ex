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
    Logger.info("Estado en la replica: #{inspect state}")
    { :noreply, Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Logger.info("Llegue al if: #{inspect element}")
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
