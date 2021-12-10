defmodule ArchitectureTest do
  use ExUnit.Case
  require Logger
  import Mock

  # To run one test: mix test test/architecture_test.exs --only <tag_name>

  # Application.ensure_all_started(:carpincho_mq) levanta toda la app en el nodo

  # usamos LocalCluster para crear varios nodos
  # se tarda un poco en levantar la cola, la replica, tirar un nodo, relevantar una cola, por eso tiré sleeps, aunque se que no es lo mejor

  # Schism.partition(group2) crea una particion, Schism.heal(nodes) vuelve a unir a todos los nodos
  setup_with_mocks([
    {UDPServer, [], [send_message: fn(queue_name, message, subscriber) -> Logger.info "The consumer: #{subscriber} received the message: #{message.payload}" end]},
    {PrimaryQueue, [:passthrough], [schedule_retry_call: fn(message) -> Logger.info "Scheduling retry call for message: #{message.payload}" end]}
  ]) do
    :ok
  end

  @tag :primary_replica_nodes
  test "primary and replica queue are created in different nodes" do
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, _, _] = nodes
    Enum.each(nodes, &Node.spawn(&1, __MODULE__, :initialize, []))

    Process.sleep(3000)

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, PubSub, :transactional])

    Process.sleep(3000)

    primary_queue_node = Utils.where_is(primary_pid, nodes)
    replica_queue_node = Utils.where_is(replica_pid, nodes)
    Logger.info "Primary Queue is in node: #{primary_queue_node}"
    Logger.info "Replica Queue is in node: #{replica_queue_node}"
    assert primary_queue_node != replica_queue_node
  end

  @tag :node_down_starts_queue_again
  test "if the node that contains the primary queue breaks, the primary queue is started in another node" do
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, _, _] = nodes
    Enum.each(nodes, &Node.spawn(&1, __MODULE__, :initialize, []))

    Process.sleep(3000)

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, PubSub, :transactional])

    Process.sleep(3000)

    Logger.info "Primary Queue: #{inspect Utils.where_is(primary_pid, nodes)}"
    Logger.info "Replica Queue: #{inspect Utils.where_is(replica_pid, nodes)}"
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
    nodes = LocalCluster.start_nodes("carpincho", 3, files: [__ENV__.file])

    [node1, _, _] = nodes
    Enum.each(nodes, &Node.spawn(&1, __MODULE__, :initialize, []))

    Process.sleep(3000)

    {:ok, {primary_pid, _}} = :rpc.call(node1, Queue, :new, [:cola1, 345, PubSub, :transactional])

    Process.sleep(3000)

    :rpc.call(node1, Consumer, :subscribe, [:cola1, :consumer1])
    :rpc.call(node1, Producer, :push_message, [:cola1, "Holanda"])
    :rpc.call(node1, Producer, :push_message, [:cola1, "Chaucha"])

    old_node = Utils.where_is(primary_pid, nodes)

    LocalCluster.stop_nodes([old_node])

    Process.sleep(3000)

    alive_node = Enum.find(nodes, fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    {:ok, primary_queue_state} = :rpc.call(alive_node, Queue, :state, [:cola1])
    {:ok, replica_queue_state} = :rpc.call(alive_node, Queue, :state, [:cola1_replica])

    Logger.info "The PrimaryQueue elements are: #{inspect primary_queue_state.elements}"
    Logger.info "The ReplicaQueue elements are: #{inspect replica_queue_state.elements}"
    assert length(primary_queue_state.elements) == 2
    assert primary_queue_state.elements == replica_queue_state.elements
  end

  @tag :partition
  test "what happen if we have a partition and then connection is healed, the queues are merged into one" do
    nodes = LocalCluster.start_nodes("carpincho", 4, files: [__ENV__.file])

    [node1, node2, node3, node4] = nodes
    Enum.each(nodes, &Node.spawn(&1, __MODULE__, :initialize, []))

    Process.sleep(3000)

    {:ok, {_, _}} = :rpc.call(node1, Queue, :new, [:cola1, 345, PubSub, :transactional])

    Process.sleep(3000)

    Logger.info "Group 1 Registry: #{inspect :rpc.call(node1, Utils, :show_registry, [])}"
    Logger.info "Group 2 Registry: #{inspect :rpc.call(node3, Utils, :show_registry, [])}"
    group1 = [node1, node2]
    group2 = [node3, node4]
    Schism.partition(group1)
    Schism.partition(group2)

    Process.sleep(3000)

    Logger.info "Group 1 Registry: #{inspect :rpc.call(node1, Utils, :show_registry, [])}"
    Logger.info "Group 2 Registry: #{inspect :rpc.call(node3, Utils, :show_registry, [])}"

    Logger.info "Nodo1: #{inspect :rpc.call(node1, Node, :list, [])}"
    Logger.info "Nodo3: #{inspect :rpc.call(node3, Node, :list, [])}"

    :rpc.call(node1, Consumer, :subscribe, [:cola1, :consumer1])
    :rpc.call(node1, Producer, :push_message, [:cola1, "Holanda"])

    :rpc.call(node3, Consumer, :subscribe, [:cola1, :consumer1])
    :rpc.call(node3, Producer, :push_message, [:cola1, "Chaucha"])

    Process.sleep(3000)

    {:ok, group1_queue_state} = :rpc.call(node1, Queue, :state, [:cola1])
    {:ok, group2_queue_state} = :rpc.call(node3, Queue, :state, [:cola1])
    Logger.info "Group 1 State: #{inspect group1_queue_state}"
    Logger.info "Group 2 State: #{inspect group2_queue_state}"

    assert Enum.find(group1_queue_state.elements, fn element -> element.message.payload == "Holanda" end) != nil
    assert Enum.find(group1_queue_state.elements, fn element -> element.message.payload == "Chaucha" end) == nil

    assert Enum.find(group2_queue_state.elements, fn element -> element.message.payload == "Holanda" end) == nil
    assert Enum.find(group2_queue_state.elements, fn element -> element.message.payload == "Chaucha" end) != nil

    Schism.heal(group1)
    Schism.heal(group2)

    Process.sleep(5000)

    Logger.info "Nodo1: #{inspect :rpc.call(node1, Node, :list, [])}"
    Logger.info "Nodo3: #{inspect :rpc.call(node3, Node, :list, [])}"
    {:ok, state} = :rpc.call(node1, Queue, :state, [:cola1])
    {:ok, state_again} = :rpc.call(node3, Queue, :state, [:cola1])
    Logger.info "Group 1 State: #{inspect state}"
    assert length(state.elements) == 2
    assert length(state_again.elements) == 2
  end

  def initialize do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    receive do
    end
  end
end
