defmodule CarpinchoMQTest do
  use ExUnit.Case
  doctest Queue

  # to run tests:
  #  > epmd -daemon
  #  > mix test --no-start

  setup do
    :ok = LocalCluster.start()
    Application.ensure_all_started(:carpincho_mq)
    [node1, node2] = LocalCluster.start_nodes("my-cluster", 2)
    run = &execute(node1, &1, &2, &3)
    {:ok, _} = run.(Queue, :new, [:cola1, 345, :publish_subscribe])
    {:ok, %{node1: node1, node2: node2, run: run}}
  end

  def execute(node, module, function, args) do
    :rpc.call(node, module, function, args)
  end

  test "initial state of a just created queue is correct", state do
    run = state[:run]
    
    actual_initial_state = run.(Queue, :state, [:cola1])
    
    expected_initial_state = %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
    assert expected_initial_state == actual_initial_state
  end

  test "consumer suscribes succesfully", state do
    run = state[:run]
    
    {:ok, consumer} = run.(Consumer, :start_link, [])
    run.(Queue, :call, [:cola1, { :subscribe, consumer }])
    actual_state = run.(Queue, :state, [:cola1])
    
    assert [consumer] == actual_state.subscribers
  end
end
