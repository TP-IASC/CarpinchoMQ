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
      { :reply, Errors.error(:max_size_exceded, "Queue max size (#{state.max_size}) cannot be exceded"), state }
    else
      new_message = create_message(payload)

      Queue.replica_name(state.name)
      |> Queue.cast({ :push, new_message })

      { :reply, :message_queued, Map.put(state, :elements, [new_message|state.elements]) }
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    if Enum.member?(state.subscribers, pid) do
      { :reply, :already_subscribed, state }
    else
      Queue.replica_name(state.name)
      |> Queue.cast({ :subscribe, pid })
      { :reply, :subscribed, Map.put(state, :subscribers, [pid|state.subscribers]) }
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    unless Enum.member?(state.subscribers, pid) do
      { :reply, :not_subscribed, state }
    else
      Queue.replica_name(state.name)
      |> Queue.cast({ :unsubscribe, pid })

      { :reply, :unsubscribed, Map.put(state, :subscribers, List.delete(state.subscribers, pid)) }
    end
  end
end
