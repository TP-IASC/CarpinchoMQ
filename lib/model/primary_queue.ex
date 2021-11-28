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

      { :reply, OK.success(:message_queued), Map.put(state, :elements, [new_message|state.elements]) }
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

  def handle_cast({:delete, message}, state) do
    send_to_replica(state.name, {:delete, message})

    { :noreply, Map.put(state, :elements, List.delete(state.elements, message)) }
  end

  def handle_cast({:send_to_subscribers, message}, state) do
    queue_name = state.name
    if (Enum.empty?(state.subscribers)) do
      Logger.warning("The queue \"#{queue_name}\" has not subscribers to send the message")
    else
      non_ack_subscribers = state.subscribers
      |> Enum.map(fn subscriber -> Consumer.send_message(subscriber, message, queue_name) end)
      |> Enum.filter(fn result -> result != :ack end)

      unless (Enum.empty?(non_ack_subscribers)) do
        Logger.error("The message \"#{message.payload}\" wasn't able to receive by all the subscribers from the queue \"#{queue_name}\"")
      else
        Queue.cast(queue_name, {:delete, message})
      end
    end

    { :noreply, state }
  end

  defp send_to_replica(queue_name, request) do
    Queue.replica_name(queue_name)
      |> Queue.cast(request)
  end
end
