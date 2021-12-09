defmodule ArchitectureTest do
  use ExUnit.Case
  require Logger

  # To run one test: mix test test/architecture_test.exs --only <tag_name>

  @tag :primary_replica
  test "primary and replica queue are created in different nodes" do 
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, _, _] = nodes

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])
    
    Process.sleep(3000)

    primary_queue_node = Utils.where_is(primary_pid, nodes)
    replica_queue_node = Utils.where_is(replica_pid, nodes)
    Logger.info "Primary Queue is in node: #{primary_queue_node}"
    Logger.info "Replica Queue is in node: #{replica_queue_node}"
    assert primary_queue_node != replica_queue_node
  end

  @tag :node_down
  test "if the node that contains the primary queue breaks, the primary queue is started in another node" do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("my-cluster", 3, files: [__ENV__.file])

    [node1, node2, node3] = nodes

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    Process.sleep(3000)

    old_node = Utils.where_is(primary_pid, nodes)
    LocalCluster.stop_nodes([old_node])

    Process.sleep(3000)

    alive_node = Enum.find(nodes, fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    new_primary_pid = :rpc.call(alive_node, Queue, :whereis, [:cola1])
    new_node = Utils.where_is(new_primary_pid, nodes)

    Logger.info "New Node #{inspect new_node}"
    Logger.info "Old Node #{inspect old_node}"

    assert old_node != new_node
  end

  #test "if the node that contains the primary queue breaks, the primary queue state comes from his replica" do 
    
  #end

  #test "what happen if we have a partition" do
    
  #end

  #test "every node must have a udp and http server" do
    
  #end
end