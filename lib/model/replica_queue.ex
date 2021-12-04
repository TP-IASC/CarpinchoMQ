defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(default_state) do
    info(default_state.name, "queue started")
    Process.flag(:trap_exit, true)
    { :ok, default_state }
  end

  def handle_continue(:check_replica, default_state) do
    primary = Queue.primary_name(default_state.name)

    state = if Queue.alive?(primary) do
      debug(default_state.name, "restored from primary queue")
      Queue.state(primary) |> Map.put(:name, default_state.name)
    else
      default_state
    end

    { :noreply, state }
  end

  def handle_cast({:push, message}, state) do
    { :noreply, Map.put(state, :elements, [%{message: message, consumers_that_did_not_ack: []}|state.elements]) }
  end

  def handle_cast({:delete, element}, state) do
    { :noreply, Map.put(state, :elements, List.delete(state.elements, element)) }
  end

  def handle_cast({:subscribe, consumer}, state) do
    { :noreply, Map.put(state, :subscribers, [consumer|state.subscribers]) }
  end

  def handle_cast({:unsubscribe, consumer}, state) do
    { :noreply, Map.put(state, :subscribers, List.delete(state.subscribers, consumer)) }
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

  def handle_cast({:ack, message_id, consumer}, state) do
    { :noreply, Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message.id == message_id do
        Map.put(element, :consumers_that_did_not_ack, List.delete(element.consumers_that_did_not_ack, consumer))
      else
        element
      end
    end)) }
  end
end
