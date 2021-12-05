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
    { :noreply, add_new_element(state, message) }
  end

  def handle_cast({:delete, element}, state) do
    { :noreply, delete_element(state, element) }
  end

  def handle_cast({:subscribe, pid}, state) do
    { :noreply, add_subscriber(state, pid) }
  end

  def handle_cast({:unsubscribe, pid}, state) do
    { :noreply, remove_subscriber(state, pid) }
  end

  def handle_cast({:add_receivers_to_state_message, subscribers, message}, state) do
    { :noreply, update_specific_element(state, message, &(init_element(&1, subscribers))) }
  end

  def handle_cast({:update_next_subscriber_to_send, next_subscriber_to_send}, state) do
    { :noreply, update_next_subscriber(state, next_subscriber_to_send) }
  end

  def handle_cast({:send_ack, message, consumer_pid}, state) do
    { :noreply, update_specific_element(state, message, &(update_consumers_that_did_not_ack(&1, consumer_pid))) }
  end

  def handle_cast({:message_attempt_timeout, message}, state) do
    { :noreply, update_specific_element(state, message, &(increase_number_of_attempts(&1))) }
  end
end
