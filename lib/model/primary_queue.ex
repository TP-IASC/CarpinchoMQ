defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(default_state) do
    Logger.info "Queue: #{default_state.name} started"
    Process.flag(:trap_exit, true)
    {:ok, default_state, {:continue, :check_replica}}
  end

  def handle_continue(:check_replica, default_state) do
    replica = Queue.replica_name(default_state.name)
    state = if Queue.alive?(replica), do: Queue.state(replica) |> Map.put(:name, default_state.name), else: default_state
    {:noreply, state}
  end

  def handle_call({:push, payload}, _from, state) do
    size = Enum.count(state.elements)
    if size >= state.max_size do
      {:reply, OK.failure({:max_size_exceded, "Queue max size (#{state.max_size}) cannot be exceded"}), state}
    else
      new_message = create_message(payload)
      send_to_replica(state.name, {:push, new_message})
      check_work_mode(state, new_message)

      {:reply, OK.success(:message_queued), add_new_element(state, new_message)}
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    if is_subscriber?(pid, state) do
      {:reply, :already_subscribed, state}
    else
      send_to_replica(state.name, {:subscribe, pid})

      {:reply, :subscribed, add_subscriber(state, pid)}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    unless is_subscriber?(pid, state) do
      {:reply, :not_subscribed, state}
    else
      send_to_replica(state.name, {:unsubscribe, pid})

      { :reply, :unsubscribed, remove_subscribers(state, [pid]) }
    end
  end

  def handle_info({:message_attempt_timeout, message}, state) do
    queue_name = state.name

    element = get_element_by_message(state, message)
    unless element == nil or got_all_acks?(element) do
      if rem(element.number_of_attempts, 5) == 0 do
        Logger.error "Handling message #{message.payload} after sending it 5 times. Consumers that didn't answer: #{inspect element.consumers_that_did_not_ack}"
        case state.work_mode do
          :publish_subscribe -> 
            Queue.cast(state.name, {:delete, element})
            Queue.cast(state.name, {:delete_dead_subscribers, element.consumers_that_did_not_ack})
          :work_queue -> Queue.cast(state.name, {:send_to_subscriber, message})
        end
        {:noreply, state}
      else
        new_state = update_specific_element(state, message, &(increase_number_of_attempts(&1)))
        Logger.info "Retrying send message #{message.payload} to consumers: #{inspect element.consumers_that_did_not_ack}. Attempt Nr. #{element.number_of_attempts + 1}"
        send_message_to(message, element.consumers_that_did_not_ack, queue_name)
        send_to_replica(state.name, {:message_attempt_timeout, message})
        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:send_ack, message, consumer_pid}, state) do
    new_state = update_specific_element(state, message, &(update_consumers_that_did_not_ack(&1, [consumer_pid])))

    element = get_element_by_message(new_state, message)
    unless element == nil do
      Logger.info "Got an ACK of message #{message.payload}, from consumer: #{inspect consumer_pid}"
      if got_all_acks?(element) do
        Logger.info "Got all ACKs of message #{message.payload}"
        Queue.cast(state.name, {:delete, element})
      end

      send_to_replica(state.name, {:send_ack, message, consumer_pid})
    end

    {:noreply, new_state}
  end

  def handle_cast({:delete, element}, state) do
    send_to_replica(state.name, {:delete, element})
    { :noreply, delete_element(state, element) }
  end

  def handle_cast({:delete_dead_subscribers, subscribers_to_delete}, state) do
    send_to_replica(state.name, {:delete_dead_subscribers, subscribers_to_delete})
    { :noreply, delete_subscribers(state, subscribers_to_delete) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    all_subscribers = state.subscribers
    if Enum.empty?(all_subscribers) do
      Logger.warning "The queue #{queue_name} has not subscribers to send the message #{message.payload}"
      {:noreply, state}
    else
      send_message_to(message, all_subscribers, queue_name)
      {:noreply, add_receivers_to_state_message(state, all_subscribers, message)}
    end
  end

  def handle_cast({:send_to_subscriber, message}, state) do
    queue_name = state.name
    all_subscribers = state.subscribers
    if Enum.empty?(all_subscribers) do
      Logger.warning "The queue #{queue_name} has no subscribers to send the message #{message.payload}"
      {:noreply, state}
    end
    if length(all_subscribers) == state.next_subscriber_to_send  do
      subscriber_to_send = Enum.at(all_subscribers, 0)
      send_message_to(message, [subscriber_to_send], queue_name)
      new_state = update_next_subscribers_and_replica(state, 1)
                  |> add_receivers_to_state_message([subscriber_to_send], message)
      {:noreply, new_state}
    else
      subscriber_to_send = Enum.at(all_subscribers, state.next_subscriber_to_send)
      send_message_to(message, [subscriber_to_send], queue_name)
      new_state = update_next_subscribers_and_replica(state, state.next_subscriber_to_send + 1)
                  |> add_receivers_to_state_message([subscriber_to_send], message)
      {:noreply, new_state}
    end
  end

  defp is_subscriber?(pid, state) do
    Enum.member?(state.subscribers, pid)
  end

  defp send_message_to(message, subscribers, queue_name) do
    Enum.each(subscribers, fn subscriber ->
      Consumer.cast(subscriber, { :send_message, message, subscriber, queue_name })
    end)
    schedule_retry_call(message)
  end

  defp add_receivers_to_state_message(state, subscribers, message) do
    send_to_replica(state.name, { :add_receivers_to_state_message, subscribers, message })
    update_specific_element(state, message, &(init_sent_element_props(&1, subscribers)))
  end

  defp update_next_subscribers_and_replica(state, next_subscriber_to_send) do
    send_to_replica(state.name, {:update_next_subscriber_to_send, next_subscriber_to_send})
    update_next_subscriber(state, next_subscriber_to_send)
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end

  defp schedule_retry_call(message) do
    Process.send_after(self(), {:message_attempt_timeout, message}, 4000)
  end

  defp check_work_mode(state, new_message) do
    case state.work_mode do
      :publish_subscribe -> Queue.cast(state.name, {:send_to_subscribers, new_message})
      :work_queue -> Queue.cast(state.name, {:send_to_subscriber, new_message})
    end
    {:noreply, state}
  end

  defp get_element_by_message(state, message), do: Enum.find(state.elements, &(&1.message == message))
end
