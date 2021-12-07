defmodule CarpinchoMQTest do
  use ExUnit.Case
  doctest Queue

  setup_all do
    [node1, node2] = LocalCluster.start_nodes("my-cluster", 2)
    {:ok, %{node1: node1, node2: node2, run: &execute(node1, &1, &2, &3)}}
  end

  def execute(node, module, function, args) do
    :rpc.call(node, module, function, args)
  end

  test "initial state of a just created queue is correct", state do
    run = state[:run]
    
    {:ok, _} = run.(Queue, :new, [:cola1, 345, :publish_subscribe])
    actual_initial_state = run.(Queue, :state, [:cola1])
    
    expected_initial_state = %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
    assert expected_initial_state == actual_initial_state
  end
end
