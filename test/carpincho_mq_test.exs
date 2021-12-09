defmodule CarpinchoMQTest do
  use ExUnit.Case
  require Logger
  import ExUnit.CaptureLog
  import Mock

  # to run tests:
  #  > epmd -daemon
  #  > mix test

  setup do
    topologies = Application.get_env(:libcluster, :topologies)
    start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
    start_supervised(App.HordeRegistry)
    start_supervised({ App.HordeSupervisor, [strategy: :one_for_one] })
    start_supervised(App.NodeObserver.Supervisor)
    
    {:ok, {primary_queue_pid, replica_queue_pid}} = Producer.new_queue(:cola1, 345, :publish_subscribe)
    :ok
  end

  setup_with_mocks([
    {Consumer, [:passthrough], [cast: fn(consumer_pid, { :send_message, message, subscriber, _ }) -> Logger.info "The consumer: #{subscriber} received the message: #{message.payload}" end]},
    {Queue, [:passthrough], [create_message: fn(payload) -> %{id: :"1", timestamp: ~U[2021-12-08 01:32:41.164744Z], payload: payload} end]},
    {PrimaryQueue, [:passthrough], [schedule_retry_call: fn(message) -> Logger.info "Scheduling retry call for message: #{message.payload}" end]}
  ]) do
    :ok
  end

  test "initial state of a just created queue is correct" do    
    actual_initial_state = Queue.state(:cola1)
    
    expected_initial_state = %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
    assert expected_initial_state == actual_initial_state
  end

  test "work mode can only be :publish_subscribe or :work_queue" do
    non_existent_work_mode_error = {:error,{:non_existent_work_mode, "Work mode :hola does not exist. Available work modes: :publish_subscribe and :work_queue"}}
    assert Producer.new_queue(:cola2, 45, :hola) == non_existent_work_mode_error
  end

  test "consumer suscribes successfully" do
    :subscribed = Consumer.subscribe(:cola1, :consumer1)
    assert [:consumer1] == Queue.state(:cola1).subscribers

    :subscribed = Consumer.subscribe(:cola1, :consumer2)
    assert [:consumer1, :consumer2] == Queue.state(:cola1).subscribers
  end

  test "consumer can't suscribe if it is already suscribed" do
    Consumer.subscribe(:cola1, :consumer1)
    assert :already_subscribed = Consumer.subscribe(:cola1, :consumer1)
  end

  test "consumer unsuscribes succesfully" do
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)

    :unsubscribed = Consumer.unsubscribe(:cola1, :consumer1)
    assert [:consumer2] == Queue.state(:cola1).subscribers

    :unsubscribed = Consumer.unsubscribe(:cola1, :consumer2)
    assert [] == Queue.state(:cola1).subscribers
  end

  test "consumer can't unsuscribe if it is not suscribed" do
    assert :not_subscribed == Consumer.unsubscribe(:cola1, :consumer1)
  end

  test "new element is successfully added" do
    Consumer.subscribe(:cola1, :consumer1)

    assert [] == Queue.state(:cola1).elements
    {:ok, :message_queued} = Producer.push_message(:cola1, "It's a trap! - Almirant Ackbar")
    
    expected_queue_elements = [%{consumers_that_did_not_ack: [:consumer1], message: %{id: :"1", payload: "It's a trap! - Almirant Ackbar", timestamp: ~U[2021-12-08 01:32:41.164744Z]}, number_of_attempts: 1}]
    assert expected_queue_elements == Queue.state(:cola1).elements
  end

  test "max size cannot be exceded" do
    Producer.new_queue(:cola2, 1, :publish_subscribe)
    Consumer.subscribe(:cola2, :consumer1)
    Producer.push_message(:cola2, "It's a trap! - Almirant Ackbar")

    max_size_exceded_error = {:error, {:max_size_exceded, "Queue max size (1) cannot be exceded"}}
    assert max_size_exceded_error = Producer.push_message(:cola2, "Exceed the max size, you should not - Yoda")
  end

  test "the queue has not subscribers to send the message" do
    log_captured = capture_log([level: :warning], fn -> 
      Producer.push_message(:cola1, "¡Hello There! - Obi Wan Kenobi")
    end) 
    assert log_captured =~ "The queue cola1 has not subscribers to send the message: ¡Hello There! - Obi Wan Kenobi"
  end

  test "the queue sends the message to all subscribers if it has pub-sub work mode" do
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)

    logs_captured = capture_log([level: :info], fn -> 
      Producer.push_message(:cola1, "General Kenobi... - Grievous")
    end)
    assert logs_captured =~ "The consumer: consumer1 received the message: General Kenobi... - Grievous"
    assert logs_captured =~ "The consumer: consumer2 received the message: General Kenobi... - Grievous"
  end

  test "the queue sends the message to next subscriber if it has work-queue work mode" do
    Producer.new_queue(:cola2, 10, :work_queue)
    Consumer.subscribe(:cola2, :consumer1)
    Consumer.subscribe(:cola2, :consumer2)

    first_log_captured = capture_log([level: :info], fn -> 
      Producer.push_message(:cola2, "¡Hello There! - Obi Wan Kenobi")
    end)
    assert first_log_captured =~ "The consumer: consumer1 received the message: ¡Hello There! - Obi Wan Kenobi"      

    second_log_captured = capture_log([level: :info], fn -> 
      Producer.push_message(:cola2, "General Kenobi... - Grievous")
    end)
    assert second_log_captured =~ "The consumer: consumer2 received the message: General Kenobi... - Grievous"
  end

  test "receiving one ack for a specific message" do
    specific_message = "I'm not afraid! - Luke Skywalker"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)
    Producer.push_message(:cola1, specific_message)
    Producer.push_message(:cola1, "You will be - Yoda")

    elements_after_push = Queue.state(:cola1).elements
    first_pushed_element = List.last(elements_after_push)
    assert [:consumer1, :consumer2] == first_pushed_element.consumers_that_did_not_ack

    log_captured = capture_log([level: :info], fn ->
      Queue.cast(:cola1, {:send_ack, first_pushed_element.message, :consumer1})
    end)

    assert log_captured =~ "Got an ACK of message #{specific_message}, from consumer: :consumer1"

    elements = Queue.state(:cola1).elements
    
    assert [:consumer2] == List.last(elements).consumers_that_did_not_ack
    assert [:consumer1, :consumer2] == List.first(elements).consumers_that_did_not_ack
  end

  test "receiving all acks for a specific message" do
    specific_message = "I'm not afraid! - Luke Skywalker"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)
    Producer.push_message(:cola1, specific_message)
    Producer.push_message(:cola1, "You will be - Yoda")

    elements_after_push = Queue.state(:cola1).elements
    first_pushed_element = List.last(elements_after_push)
    assert [:consumer1, :consumer2] == first_pushed_element.consumers_that_did_not_ack
    assert 2 == length(elements_after_push)

    first_log_captured = capture_log([level: :info], fn ->
      Queue.cast(:cola1, {:send_ack, first_pushed_element.message, :consumer1})
    end)
    assert first_log_captured =~ "Got an ACK of message #{specific_message}, from consumer: :consumer1"

    second_log_captured = capture_log([level: :info], fn ->
      Queue.cast(:cola1, {:send_ack, first_pushed_element.message, :consumer2})
    end)
    assert second_log_captured =~ "Got an ACK of message #{specific_message}, from consumer: :consumer2"
    assert second_log_captured =~ "Got all ACKs of message #{specific_message}"

    elements_after_acks = Queue.state(:cola1).elements
    assert 1 == length(elements_after_acks)
    assert [:consumer1, :consumer2] == List.first(elements_after_acks).consumers_that_did_not_ack
  end

  test "retrying sending a message" do

  end

  test "5 attempts - pub-sub work mode" do
    
  end

  test "5 attempts - work-queue work mode" do
    
  end
end
