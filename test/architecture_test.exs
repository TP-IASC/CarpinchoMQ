defmodule ArchitectureTest do
  use ExUnit.Case
  require Logger

  setup do
    #topologies = Application.get_env(:libcluster, :topologies)
    #start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
    #start_supervised(App.HordeRegistry)
    #start_supervised({ App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] })
    #start_supervised(App.NodeObserver.Supervisor)
    #Application.ensure_all_started(:carpincho_mq)

    nodes = LocalCluster.start_nodes("my-cluster", 3, files: [__ENV__.file])
    [node1, node2, node3] = nodes
    
    Enum.each(nodes, &Node.spawn(&1, __MODULE__, :initialize, []))

    Process.sleep(1000)

    {:ok, %{node1: node1, node2: node2, node3: node3}}
  end

  def initialize do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    #{:ok, _} = App.HordeRegistry.start_link("")
    #{:ok, _} = App.HordeSupervisor.start_link([strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active])
  end

  test "cannot create a queue that already exists", state do
    node1 = state[:node1]  
    {:ok, _} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])
    assert {:error, {:queue_already_exists, "A queue named :cola1 already exists"}} == :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])
  end

  test "primary and replica queue are created in different nodes", state do 
    node1 = state[:node1]

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    assert where_is(primary_pid, state) != where_is(replica_pid, state)
  end

  test "if the node that contains the primary queue breaks, the primary queue is started in another node", state do
    node1 = state[:node1]
    node2 = state[:node2]
    node3 = state[:node3]

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    old_node = where_is(primary_pid, state)
    LocalCluster.stop_nodes([old_node])

    alive_node = Enum.find([node1, node2, node3], fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    new_primary_pid = :rpc.call(alive_node, Queue, :whereis, [:cola1])
    new_node = where_is(new_primary_pid, state)
    
    assert old_node != new_node
  end

  test "if the node that contains the primary queue breaks, the primary queue state comes from his replica" do 
    
  end

  test "what happen if we have a partition" do
    
  end

  test "every node must have a udp and http server" do
    
  end

  defp where_is(queue, state) do
    cond do
      get_processes(state.node1) |> queue_exists?(queue) -> state.node1
      get_processes(state.node2) |> queue_exists?(queue) -> state.node2
      get_processes(state.node3) |> queue_exists?(queue) -> state.node3
    end
  end

  defp get_processes(node), do: :rpc.call(node, Process, :list, [])

  defp queue_exists?(processes, queue) do
    if processes == {:badrpc, :nodedown} do
      false
    else
      Enum.member?(processes, queue)
    end
  end
end