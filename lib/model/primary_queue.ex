defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(default_state) do
    info(default_state.name, "queue started")
    Process.flag(:trap_exit, true)
    { :ok, default_state, { :continue, :check_replica } }
  end

  def handle_continue(:check_replica, default_state) do
    replica = Queue.replica_name(default_state.name)
    state = if Queue.alive?(replica) do
      debug(default_state.name, "restored from replica")
      Queue.state(replica) |> Map.put(:name, default_state.name)
    else
      default_state
    end

    { :noreply, state }
  end

  def handle_call({:push, payload}, _from, state) do
    size = Enum.count(state.elements)
    if size >= state.max_size do
      { :reply, OK.failure({:max_size_exceded, "queue max size (#{state.max_size}) cannot be exceded"}), state }
    else
      new_message = create_message(payload)

      send_to_replica(state.name, { :push, new_message })

      if state.work_mode == :publish_subscribe, do: Queue.cast(state.name, {:send_to_subscribers, new_message})

      { :reply, OK.success(:message_queued), add_new_element(state, new_message) }
    end
  end

  def handle_call({:subscribe, consumer}, _from, state) do
    if is_subscriber?(consumer, state) do
      { :reply, :already_subscribed, state }
    else
      send_to_replica(state.name, { :subscribe, consumer })
      debug(state.name, "subscribed #{inspect(consumer)}")
      { :reply, :subscribed, add_subscriber(state, consumer) }
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    unless is_subscriber?(subscriber, state) do
      { :reply, :not_subscribed, state }
    else
      send_to_replica(state.name, { :unsubscribe, subscriber })
      debug(state.name, "unsubscribed #{inspect(subscriber)}")
      { :reply, :unsubscribed, remove_subscriber(state, subscriber) }
    end
  end

  def handle_info({:message_attempt_timeout, message}, state) do
    queue_name = state.name

    element = get_element_by_message(state, message.id)
    unless element == nil or Enum.empty?(element.consumers_that_did_not_ack) do
      if element.number_of_attempts == 5 do
        warning(state.name, "Discarding message #{inspect(message)} after sending it 5 times. Consumers that didn't answer: #{inspect element.consumers_that_did_not_ack}.")
        Queue.cast(state.name, {:delete, element})
        {:noreply, state}
      else
        new_state = update_specific_element(state, message.id, &(increase_number_of_attempts(&1)))
        debug(state.name, "retrying send message #{message.id} to consumers: #{inspect element.consumers_that_did_not_ack}. Attempt Nr. #{element.number_of_attempts + 1}")
        send_message_to(message, element.consumers_that_did_not_ack, queue_name)
        send_to_replica(state.name, {:message_attempt_timeout, message})
        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:ack, message_id, consumer}, state) do
    new_state = update_specific_element(state, message_id, &(update_consumers_that_did_not_ack(&1, consumer)))

    element = get_element_by_message(new_state, message_id)
    unless element == nil do
      debug(state.name, "message #{message_id} acknowledged by #{inspect(consumer)}")
      if Enum.empty?(element.consumers_that_did_not_ack) do
        debug(state.name, "message #{message_id} received all ACKs")
        Queue.cast(state.name, {:delete, element})
      end

      send_to_replica(state.name, { :ack, message_id, consumer })
    end

    { :noreply, new_state }
  end

  def handle_cast({:delete, element}, state) do
    send_to_replica(state.name, {:delete, element})
    debug(state.name, "message #{inspect(element.message)} deleted")
    { :noreply, delete_element(state, element) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    all_subscribers = state.subscribers
    if Enum.empty?(all_subscribers) do
      warning(queue_name, "not enough subscribers to send the message")
      { :noreply, state }
    else
      send_message_to(message, all_subscribers, queue_name)
      { :noreply, add_receivers_to_state_message(state, all_subscribers, message) }
    end
  end

  defp is_subscriber?(consumer, state) do
    Enum.member?(state.subscribers, consumer)
  end

  defp send_message_to(message, subscribers, queue_name) do
    Enum.each(subscribers, fn subscriber ->
      debug(queue_name, "message #{inspect(message)} sent to #{inspect(subscriber)}")
      GenServer.cast(UDPServer, { :send_message, queue_name, message, subscriber })
    end)
    schedule_retry_call(message)
  end

  defp add_receivers_to_state_message(state, subscribers, message) do
    send_to_replica(state.name, { :add_receivers_to_state_message, subscribers, message })
    update_specific_element(state, message.id, &(init_element(&1, subscribers)))
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end

  defp schedule_retry_call(message) do
    Process.send_after(self(), {:message_attempt_timeout, message}, 4000)
  end

  defp get_element_by_message(state, message_id), do: Enum.find(state.elements, &(&1.message.id == message_id))
end
