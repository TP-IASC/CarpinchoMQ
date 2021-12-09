defmodule ArchitectureTest do
  use ExUnit.Case
  require Logger

  # To run one test: mix test test/architecture_test.exs --only <tag_name>

  @tag :primary_replica_nodes
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

  @tag :node_down_starts_queue_again
  test "if the node that contains the primary queue breaks, the primary queue is started in another node" do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, _, _] = nodes

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    Process.sleep(3000)

    old_node = Utils.where_is(primary_pid, nodes)
    LocalCluster.stop_nodes([old_node])

    Process.sleep(3000)

    alive_node = Enum.find(nodes, fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    new_primary_pid = :rpc.call(alive_node, Queue, :whereis, [:cola1])
    new_node = Utils.where_is(new_primary_pid, nodes)

    Logger.info "The Primary Queue is on node: #{inspect new_node}"
    Logger.info "The Primary Queue was on node: #{inspect old_node}"

    assert old_node != new_node
  end

  @tag :node_down_starts_queue_again_with_state
  test "if the node that contains the primary queue breaks, the primary queue state comes from his replica" do 
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, node2, node3] = nodes

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    Process.sleep(3000)

    :rpc.call(node1, Producer, :push_message, [:cola1, "Holanda"])
    :rpc.call(node1, Producer, :push_message, [:cola1, "Chaucha"])

    old_node = Utils.where_is(primary_pid, nodes)

    LocalCluster.stop_nodes([old_node])

    Process.sleep(3000)

    alive_node = Enum.find(nodes, fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    primary_queue_state = :rpc.call(alive_node, Queue, :state, [:cola1])
    replica_queue_state = :rpc.call(alive_node, Queue, :state, [:cola1_replica])

    Logger.info "The PrimaryQueue elements are: #{inspect primary_queue_state.elements}"
    Logger.info "The ReplicaQueue elements are: #{inspect replica_queue_state.elements}"
    assert length(primary_queue_state.elements) == 2
    assert primary_queue_state.elements == replica_queue_state.elements
  end

  @tag :partition
  test "what happen if we have a partition and then connection is healed, the queues are merged into one" do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("carpincho", 4, files: [__ENV__.file])

    [node1, node2, node3, node4] = nodes

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    Process.sleep(3000)

    Logger.info "Group 1 Registry: #{inspect :rpc.call(node1, Utils, :show_registry, [])}"
    Logger.info "Group 2 Registry: #{inspect :rpc.call(node3, Utils, :show_registry, [])}"
    group1 = [node1, node2]
    group2 = [node3, node4]
    Schism.partition(group1)
    Schism.partition(group2)

    Process.sleep(10000)

    Logger.info "Group 1 Registry: #{inspect :rpc.call(node1, Utils, :show_registry, [])}"
    Logger.info "Group 2 Registry: #{inspect :rpc.call(node3, Utils, :show_registry, [])}"

    :rpc.call(node1, Producer, :push_message, [:cola1, "Holanda"])
    :rpc.call(node3, Producer, :push_message, [:cola1, "Chaucha"])

    Process.sleep(10000)

    group1_queue_state = :rpc.call(node1, Queue, :state, [:cola1])
    group2_queue_state = :rpc.call(node3, Queue, :state, [:cola1])
    Logger.info "Group 1 State: #{inspect group1_queue_state}"
    Logger.info "Group 2 State: #{inspect group2_queue_state}"
  end
end