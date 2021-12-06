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
    { :noreply, add_new_element(state, message) }
  end

  def handle_cast({:delete, element}, state) do
    { :noreply, delete_element(state, element) }
  end

  def handle_cast({:subscribe, consumer}, state) do
    { :noreply, add_subscriber(state, consumer) }
  end

  def handle_cast({:unsubscribe, consumer}, state) do
    { :noreply, remove_subscriber(state, consumer) }
  end

  def handle_cast({:add_receivers_to_state_message, subscribers, message}, state) do
    { :noreply, update_specific_element(state, message, &(init_element(&1, subscribers))) }
  end

  def handle_cast({:ack, message_id, consumer}, state) do
    { :noreply, update_specific_element(state, message_id, &(update_consumers_that_did_not_ack(&1, consumer))) }
  end

  def handle_cast({:message_attempt_timeout, message}, state) do
    { :noreply, update_specific_element(state, message.id, &(increase_number_of_attempts(&1))) }
  end
end
