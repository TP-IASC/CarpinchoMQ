defmodule MyMatchers do
  import ExUnit.Assertions
  import ExMatchers.Custom

  defmodule QueueElementsAreEqual do
    # for lists of elements with the same size
    def to_match(elements, other_elements) do
      assert are_equal(elements, other_elements)
    end

    def to_not_match(elements, other_elements) do
      refute are_equal(elements, other_elements)
    end

    defp are_equal(elements, other_elements) do
      case elements do
        [] -> true
        [elem] -> is_equal(elem, List.first(other_elements))
        true ->
          [head | tail] = elements
          [other_head | other_tail] = other_elements
          is_equal(head, other_head) and are_equal(tail, other_tail)
      end
    end

    defp is_equal(element, other_element) do
      (element.consumers_that_did_not_ack == other_element.consumers_that_did_not_ack and
      element.message.payload == other_element.message.payload and
      element.number_of_attempts == other_element.number_of_attempts)
    end
  end
  defmatcher be_equal(other_elements), matcher: QueueElementsAreEqual
end

defmodule CarpinchoMQTest do
  use ExUnit.Case
  use ExMatchers
  require Logger
  import ExUnit.CaptureLog
  import Mock
  import MyMatchers

  # to run tests:
  #  > epmd -daemon
  #  > mix test test/carpincho_mq_test.exs
  
  # usamos CaptureLog para poder assertear que se hizo un log en un determinado momento

  # start_supervised levanta un modulo de la app y lo supervisa el propio entorno de tests (el nodo que se levanta cuando corremos los tests)
  # , asi cada vez que termina un test
  # el propio entorno termina todo satisfactoriamente

  # usamos Mock para mockear al UDPServer y que no se le envie un mensaje
  # mockeamos el schedule_retry_call para que no se reintente el envio cada x tiempo
  # el passthrough es para que solo se mockee esa funcion, pero que todas las demas del module sean las reales
  # setup_with_mocks levanta los mocks antes de cada test (setup + test_with_mocks)

  # Acá: expect expected_queue_elements, to: be_equal(new_state.elements)
  # usamos ExMatchers para poder comparar elementos sin importar el id que tenga cada uno y el timestamp (que son random para cada mensaje)
  # creamos un ExMatcher Custom en MyMatchers (QueueElementsAreEqual)

  setup do
    topologies = Application.get_env(:libcluster, :topologies)
    start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
    start_supervised(App.HordeRegistry)
    start_supervised({ App.HordeSupervisor, [strategy: :one_for_one] })
    start_supervised(App.NodeObserver.Supervisor)

    {:ok, {primary_queue_pid, replica_queue_pid}} = Producer.new_queue(:cola1, 345, PubSub, :transactional)
    :ok
  end

  setup_with_mocks([
    {UDPServer, [], [send_message: fn(queue_name, message, subscriber) -> Logger.info "The consumer: #{subscriber} received the message: #{message.payload}" end]},
    {PrimaryQueue, [:passthrough], [schedule_retry_call: fn(message) -> Logger.info "Scheduling retry call for message: #{message.payload}" end]}
  ]) do
    :ok
  end

  test "cannot create a queue that already exists" do
    assert {:error, {:queue_already_exists, 409, "a queue named :cola1 already exists"}} == Producer.new_queue(:cola1, 345, PubSub, :transactional)
  end

  test "initial state of a just created queue is correct" do
    {:ok, actual_initial_state} = Queue.state(:cola1)

    expected_initial_state = %Queue{elements: [], max_size: 345, name: :cola1, next_subscriber_to_send: 0, queue_mode: :transactional, subscribers: [], work_mode: PubSub}
    assert expected_initial_state == actual_initial_state
  end

  test "consumer suscribes successfully" do
    {:ok, :subscribed} = Consumer.subscribe(:cola1, :consumer1)
    {_, state} = Queue.state(:cola1)
    assert [:consumer1] == state.subscribers

    {:ok, :subscribed} = Consumer.subscribe(:cola1, :consumer2)

    {_, new_state} = Queue.state(:cola1)
    assert [:consumer1, :consumer2] == new_state.subscribers
  end

  test "consumer can't suscribe if it is already suscribed" do
    Consumer.subscribe(:cola1, :consumer1)
    assert {:ok, :already_subscribed} = Consumer.subscribe(:cola1, :consumer1)
  end

  test "consumer unsuscribes succesfully" do
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)

    {:ok, :unsubscribed} = Consumer.unsubscribe(:cola1, :consumer1)
    {_, state} = Queue.state(:cola1)
    assert [:consumer2] == state.subscribers

    {:ok, :unsubscribed} = Consumer.unsubscribe(:cola1, :consumer2)

    {_, new_state} = Queue.state(:cola1)
    assert [] == new_state.subscribers
  end

  test "consumer can't unsuscribe if it is not suscribed" do
    assert {:ok, :not_subscribed} == Consumer.unsubscribe(:cola1, :consumer1)
  end

  test "new element is successfully added" do
    Consumer.subscribe(:cola1, :consumer1)

    {_, state} = Queue.state(:cola1)
    assert [] == state.elements
    {:ok, :message_queued} = Producer.push_message(:cola1, "Mensajito")

    expected_queue_elements = [%{consumers_that_did_not_ack: [:consumer1], message: %{id: :"1", payload: "Mensajito", timestamp: ~U[2021-12-08 01:32:41.164744Z]}, number_of_attempts: 1}]

    {_, new_state} = Queue.state(:cola1)
    expect expected_queue_elements, to: be_equal(new_state.elements)
  end

  test "max size cannot be exceded" do
    Producer.new_queue(:cola2, 1, PubSub, :transactional)
    Consumer.subscribe(:cola2, :consumer1)
    Producer.push_message(:cola2, "Mensaje de prueba")

    max_size_exceded_error = {:error, {:max_size_exceded, "Queue max size (1) cannot be exceded"}}
    assert max_size_exceded_error = Producer.push_message(:cola2, "Mensaje que va a exceder el limite")
  end

  test "the queue has not subscribers to send the message" do
    log_captured = capture_log(fn ->
      Producer.push_message(:cola1, "pushea2")
      Process.sleep(2000)
    end)
    assert log_captured =~ "[QUEUE] [cola1] not enough subscribers to send the message: pushea2, message discarded"
  end

  test "the queue sends the message to all subscribers if it has pub-sub work mode" do
    message = "Mensajito"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)

    logs_captured = capture_log(fn ->
      Producer.push_message(:cola1, message)
      Process.sleep(2000)
    end)
    String.match?(logs_captured, ~r/\[QUEUE\] \[cola1\] message \%\{id\: \:\\\"[[:alnum:]]*\\\"\, payload\: \\\"Mensajito\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer1/)
    String.match?(logs_captured, ~r/\[QUEUE\] \[cola1\] message \%\{id\: \:\\\"[[:alnum:]]*\\\"\, payload\: \\\"Mensajito\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer2/)
  end

  test "the queue sends the message to next subscriber if it has work-queue work mode" do
    Producer.new_queue(:cola2, 10, WorkQueue, :transactional)
    Consumer.subscribe(:cola2, :consumer1)
    Consumer.subscribe(:cola2, :consumer2)

    first_log_captured = capture_log(fn ->
      Producer.push_message(:cola2, "Mensajito")
      Process.sleep(2000)
    end)
    String.match?(first_log_captured, ~r/\[QUEUE\] \[cola2\] message \%\{id\: \:[[:alnum:]]*\, payload\: \\\"Mensajito\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer1/)

    second_log_captured = capture_log(fn ->
      Producer.push_message(:cola2, "Mensajote")
      Process.sleep(2000)
    end)
    String.match?(second_log_captured, ~r/\[QUEUE\] \[cola2\] message \%\{id\: \:[[:alnum:]]*\, payload\: \\\"Mensajote\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer2/)
  end

  test "receiving one ack for a specific message" do
    specific_message = "Mensajito"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)
    Producer.push_message(:cola1, specific_message)
    Producer.push_message(:cola1, "Mensajote")

    {_, state} = Queue.state(:cola1)
    elements_after_push = state.elements
    first_pushed_element = List.last(elements_after_push)
    assert [:consumer1, :consumer2] == first_pushed_element.consumers_that_did_not_ack

    log_captured = capture_log(fn ->
      Queue.cast(:cola1, {:ack, first_pushed_element.message.id, :consumer1})
      Process.sleep(2000)
    end)

    assert log_captured =~ ~r/\[QUEUE\] \[cola1\] message [[:alnum:]]* acknowledged by \:consumer1/

    {_, new_state} = Queue.state(:cola1)
    elements = new_state.elements

    assert [:consumer2] == List.last(elements).consumers_that_did_not_ack
    assert [:consumer1, :consumer2] == List.first(elements).consumers_that_did_not_ack
  end

  test "receiving all acks for a specific message" do
    specific_message = "Mensajito"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)
    Producer.push_message(:cola1, specific_message)
    Producer.push_message(:cola1, "Mensajote")

    {_, state} = Queue.state(:cola1)
    elements_after_push = state.elements
    first_pushed_element = List.last(elements_after_push)
    assert [:consumer1, :consumer2] == first_pushed_element.consumers_that_did_not_ack
    assert 2 == length(elements_after_push)

    first_log_captured = capture_log(fn ->
      Queue.cast(:cola1, {:ack, first_pushed_element.message.id, :consumer1})
      Process.sleep(2000)
    end)
    assert first_log_captured =~ ~r/\[QUEUE\] \[cola1\] message [[:alnum:]]* acknowledged by \:consumer1/

    second_log_captured = capture_log(fn ->
      Queue.cast(:cola1, {:ack, first_pushed_element.message.id, :consumer2})
      Process.sleep(2000)
    end)
    assert second_log_captured =~ ~r/\[QUEUE\] \[cola1\] message [[:alnum:]]* acknowledged by \:consumer2/
    assert second_log_captured =~ ~r/message [[:alnum:]]* received all ACKs/

    {_, new_state} = Queue.state(:cola1)
    elements_after_acks = new_state.elements
    assert 1 == length(elements_after_acks)
    assert [:consumer1, :consumer2] == List.first(elements_after_acks).consumers_that_did_not_ack
  end

  test "retrying sending a message" do
    specific_message = "Mensajito"
    Consumer.subscribe(:cola1, :consumer1)
    Consumer.subscribe(:cola1, :consumer2)
    Producer.push_message(:cola1, specific_message)
    Producer.push_message(:cola1, "Mensajote")

    {_, state} = Queue.state(:cola1)
    elements_after_push = state.elements
    first_pushed_element = List.last(elements_after_push)
    assert 1 == first_pushed_element.number_of_attempts

    logs_captured = capture_log(fn ->
      send(Queue.whereis(:cola1), {:message_attempt_timeout, first_pushed_element.message})
      Process.sleep(2000)
    end)

    String.match?(logs_captured, ~r/\[QUEUE\] \[cola1\] retrying send message [[:alnum:]]* to consumers\: \[\:consumer1\, \:consumer2\]\. Attempt Nr\. 2/)
    String.match?(logs_captured, ~r/\[QUEUE\] \[cola1\] message \%\{id\: \:\\\"[[:alnum:]]*\\\"\, payload\: \\\"Mensajito\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer1/)
    String.match?(logs_captured, ~r/\[QUEUE\] \[cola1\] message \%\{id\: \:\\\"[[:alnum:]]*\\\"\, payload\: \\\"Mensajito\\\"\, timestamp: \~U\[.*\]\} sent to \:consumer2/)

    {_, new_state} = Queue.state(:cola1)
    elements_after_acks = new_state.elements
    assert 2 == List.last(elements_after_acks).number_of_attempts
  end
end
