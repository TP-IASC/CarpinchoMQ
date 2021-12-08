defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(default_state) do
    info(default_state.name, "queue started")
    Process.flag(:trap_exit, true)
    { :ok, default_state }
  end

  def handle_continue(:check_replica, default_state) do
    primary = Queue.replica_name(default_state.name)
    state = OK.try do
      primary_state <- Queue.state(primary)
    after
      debug(default_state.name, "restored from primary queue")
      primary_state |> Map.put(:name, default_state.name)
    rescue
      _ -> default_state
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
    { :noreply, remove_subscribers(state, [consumer]) }
  end

  def handle_cast({:add_receivers_to_state_message, subscribers, message}, state) do
    { :noreply, update_specific_element(state, message, &(init_sent_element_props(&1, subscribers))) }
  end

  def handle_cast({:update_next_subscriber_to_send, next_subscriber_to_send}, state) do
    { :noreply, update_next_subscriber(state, next_subscriber_to_send) }
  end

  def handle_cast({:ack, message_id, consumer}, state) do
    { :noreply, update_specific_element(state, message_id, &(update_consumers_that_did_not_ack(&1, [consumer]))) }
  end

  def handle_cast({:message_attempt_timeout, message}, state) do
    { :noreply, update_specific_element(state, message.id, &(increase_number_of_attempts(&1))) }
  end

  def handle_cast({:delete_dead_subscribers, subscribers_to_delete}, state) do
    { :noreply, delete_subscribers(state, subscribers_to_delete) }
  end
end
