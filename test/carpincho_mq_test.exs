defmodule CarpinchoMQTest do
  use ExUnit.Case
  require Logger
  import Mock
  doctest Queue

  # to run tests:
  #  > epmd -daemon
  #  > mix test --no-start

  setup do
    topologies = Application.get_env(:libcluster, :topologies)
    start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
    start_supervised(App.HordeRegistry)
    start_supervised({ App.HordeSupervisor, [strategy: :one_for_one] })
    start_supervised(App.NodeObserver.Supervisor)
    
    Queue.new(:cola1, 345, :publish_subscribe)
    :ok
  end

  describe "Queue creation" do
    test "initial state of a just created queue is correct" do    
      actual_initial_state = Queue.state(:cola1)
      
      expected_initial_state = %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
      assert expected_initial_state == actual_initial_state
    end

    test "work mode can only be :publish_subscribe or :work_queue" do
      
    end
  end

  describe "Consumer Subscribing and Unsubscribing" do
    test "consumer suscribes succesfully" do
      {:ok, consumer} = Consumer.start_link
      Queue.call(:cola1, { :subscribe, consumer })
      actual_state = Queue.state(:cola1)
      
      assert [consumer] == actual_state.subscribers
    end
  
    test "consumer can't suscribe if it is already suscribed" do
      
    end
  
    test "consumer unsuscribes succesfully" do
      
    end
  
    test "consumer can't unsuscribe if it is not suscribed" do
      
    end
  end

  describe "Push Message" do
    test "new element is successfully added" do
      {:ok, consumer} = Consumer.start_link
      with_mock Consumer, [cast: fn(consumer_pid, { :send_message, message, _, _ }) -> Logger.info "El mensaje es #{message.payload}" end] do
        Queue.call(:cola1, { :subscribe, consumer })
        Producer.push_message(:cola1, "Holaa")
      end
    end

    test "the queue has not subscribers to send the message" do
      
    end
  
    test "the queue sends the message to all subscribers if it has pub-sub work mode" do
        
    end

    test "the queue sends the message to next subscriber if it has work-queue work mode" do
        
    end
  end

  describe "Receive ACK" do
    test "receiving one ack for a specific message" do
      
    end

    test "receiving all acks for a specific message" do
      
    end
  end

  describe "Message Sending Retry" do
    test "retrying sending a message" do
      
    end

    test "5 attempts - pub-sub work mode" do
      
    end

    test "5 attempts - work-queue work mode" do
      
    end
  end
end
