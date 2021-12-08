defmodule ArchitectureTest do
  use ExUnit.Case

  setup do
    :ok = LocalCluster.start()

    topologies = Application.get_env(:libcluster, :topologies)
    start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
    start_supervised(App.HordeRegistry)
    start_supervised({ App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] })
    start_supervised(App.NodeObserver.Supervisor)

    [node1, node2, node3] = LocalCluster.start_nodes("my-cluster", 3)
  
    {:ok, %{node1: node1, node2: node2, node3: node3}}
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

  test "if the node that contains the primary queue breaks, the primary queue is started in another node" do
    
  end

  test "if the node that contains the primary queue breaks, the primary queue state comes from his replica" do 
    
  end

  test "what happen if we have a partition" do
    
  end

  test "every node must have a udp and http server" do
    
  end

  defp where_is(queue, state) do
    cond do
      get_processes(state.node1) |> Enum.member?(queue) -> state.node1
      get_processes(state.node2) |> Enum.member?(queue) -> state.node2
      get_processes(state.node3) |> Enum.member?(queue) -> state.node3
    end
  end

  defp get_processes(node), do: :rpc.call(node, Process, :list, [])
end