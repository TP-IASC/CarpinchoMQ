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

      send_to_replica(state.name, { :push, new_message })

      if state.work_mode == :publish_subscribe, do: Queue.cast(state.name, {:send_to_subscribers, new_message})

      { :reply, OK.success(:message_queued), Map.put(state, :elements, [%{message: new_message, consumers_that_did_not_ack: [], number_of_attempts: 0}|state.elements]) }
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

  def handle_info({:message_attempt_timeout, message}, state) do
    Logger.info("Voy a reintentar el envio del mensajeeee")
    queue_name = state.name

    if Enum.any?(state.elements, fn element -> element.message == message end) do
      element = Enum.find(state.elements, fn element -> element.message == message end)
      unless Enum.empty?(element.consumers_that_did_not_ack) do
        if element.number_of_attempts == 5 do
          Logger.error "discarding message after sending it 5 times"
          Queue.cast(state.name, {:delete, element})
          {:noreply, state}
        else
          new_state = Map.put(state, :elements, Enum.map(state.elements, fn element ->
            if element.message == message do
              Map.put(element, :number_of_attempts, element.number_of_attempts + 1)
            else
              element
            end
          end))
          Enum.each(element.consumers_that_did_not_ack, fn consumer ->
            Consumer.cast(consumer, { :send_message, message, consumer, queue_name })
          end)
          schedule_retry_call(message)
          {:noreply, new_state}
        end
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:send_ack, message, consumer_pid}, state) do
    Logger.info "Me llego un ack de #{inspect consumer_pid}"
    # ver que pasa si un consumer contesta 2 veces
    new_state = Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        Map.put(element, :consumers_that_did_not_ack, List.delete(element.consumers_that_did_not_ack, consumer_pid))
      else
        element
      end
    end))

    elem = Enum.find(new_state.elements, fn element -> element.message == message end)
    unless elem == nil do
      if Enum.empty?(elem.consumers_that_did_not_ack) do
        Queue.cast(state.name, {:delete, elem})
      end

      send_to_replica(state.name, { :send_ack, message, consumer_pid })
    end

    { :noreply, new_state }
  end

  def handle_cast({:delete, elem}, state) do
    send_to_replica(state.name, {:delete, elem})

    { :noreply, Map.put(state, :elements, List.delete(state.elements, elem)) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    queue_subscribers = state.subscribers
    if Enum.empty?(queue_subscribers) do
      Logger.warning("The queue \"#{queue_name}\" has not subscribers to send the message")
      { :noreply, state }
    else
      Enum.each(queue_subscribers, fn subscriber ->
        Consumer.cast(subscriber, { :send_message, message, subscriber, queue_name })
      end)
      schedule_retry_call(message)
      { :noreply, add_receivers_to_state_message(state, queue_subscribers, message) }
    end
  end

  defp add_receivers_to_state_message(state, subscribers, message) do
    send_to_replica(state.name, { :add_receivers_to_state_message, subscribers, message })
    Map.put(state, :elements, Enum.map(state.elements, fn element ->
      if element.message == message do
        updated_element = Map.put(element, :consumers_that_did_not_ack, subscribers)
        Map.put(updated_element, :number_of_attempts, 1)
      else
        element
      end
    end))
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end

  defp schedule_retry_call(message) do
    Logger.info("Scheduling a retry call")
    Process.send_after(self(), {:message_attempt_timeout, message}, 2000)
  end
end
