defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(default_state) do
    Logger.info "Queue: #{default_state.name} started"
    Process.flag(:trap_exit, true)
    { :ok, default_state, { :continue, :check_replica } }
  end

  def handle_continue(:check_replica, default_state) do
    replica = Queue.replica_name(default_state.name)
    state = if Queue.alive?(replica), do: Queue.state(replica) |> Map.put(:name, default_state.name), else: default_state
    { :noreply, state }
  end

  def handle_call({:push, payload}, _from, state) do
    size = Enum.count(state.elements)
    if size >= state.max_size do
      { :reply, OK.failure({:max_size_exceded, "Queue max size (#{state.max_size}) cannot be exceded"}), state }
    else
      new_message = create_message(payload)

      #send_to_replica(state.name, { :push, new_message })

      if state.work_mode == :publish_subscribe, do: Queue.cast(state.name, {:send_to_subscribers, new_message})

      { :reply, OK.success(:message_queued), Map.put(state, :elements, [%{message: new_message, consumers_that_did_not_ack: []}|state.elements]) }
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    if Enum.member?(state.subscribers, pid) do
      { :reply, :already_subscribed, state }
    else
      send_to_replica(state.name, { :subscribe, pid })

      { :reply, :subscribed, Map.put(state, :subscribers, [pid|state.subscribers]) }
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    unless Enum.member?(state.subscribers, pid) do
      { :reply, :not_subscribed, state }
    else
      send_to_replica(state.name, { :unsubscribe, pid })

      { :reply, :unsubscribed, Map.put(state, :subscribers, List.delete(state.subscribers, pid)) }
    end
  end

  # voy recibiendo los acks
  def handle_cast({:send_ack, message, consumer_pid}, state) do
    new_state = Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, List.delete(state.subscribers, consumer_pid))
      else
        element
      end
    end))
    # borro al subscriber

    elem = Enum.find(new_state.elements, fn element -> element.message == message end)
    if Enum.empty?(elem.consumers_that_did_not_ack) do
      Queue.cast(state.name, {:delete, message})
    end
    # fijarse si ya recibio todos los acks para ese elemento -> si ya los recibio borrar el mensaje

    # sino mandarle a la replica
    { :noreply, state }
  end

  def handle_cast({:delete, message}, state) do
    # send_to_replica(state.name, {:delete, message})

    { :noreply, Map.put(state, :elements, List.delete(state.elements, fn element -> element.message == message end)) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    queue_subscribers = state.subscribers
    if Enum.empty?(queue_subscribers) do
      Logger.warning("The queue \"#{queue_name}\" has not subscribers to send the message")
      { :noreply, state }
    else
      Enum.each(queue_subscribers, fn subscriber -> Consumer.cast(subscriber, { :send_message, message, subscriber, queue_name }) end)
      { :noreply, add_receivers_to_state_message(state, queue_subscribers, message) }
    end
  end

  defp add_receivers_to_state_message(state, subscribers, message) do
    Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, subscribers)
      else
        element
      end
    end))
    # mandarle a la replica lo mismo
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end
end
