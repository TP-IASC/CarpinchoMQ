defmodule CarpinchoMQTest do
  use ExUnit.Case
  doctest Queue

  test "initial state of a just created queue is correct" do
    [node1, node2] = LocalCluster.start_nodes("my-cluster", 2)
    {:ok, {primary_queue_pid, replica_queue_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])
    
    assert :rpc.call(node1, Queue, :state, [:cola1]) == %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
  end
end
