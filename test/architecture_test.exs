defmodule ArchitectureTest do
    use ExUnit.Case
    doctest Queue

    setup do
        :ok = LocalCluster.start()

        topologies = Application.get_env(:libcluster, :topologies)
        start_supervised({ Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] })
        start_supervised(App.HordeRegistry)
        start_supervised({ App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] })
        start_supervised(App.NodeObserver.Supervisor)
    
        [node1, node2] = LocalCluster.start_nodes("my-cluster", 2)
        run = &execute(node1, &1, &2, &3)
        {:ok, _} = run.(Queue, :new, [:cola1, 345, :publish_subscribe])
        {:ok, %{run: run}}
      end
    
      def execute(node, module, function, args) do
        :rpc.call(node, module, function, args)
      end
    
      test "example", state do
        run = state[:run]
        
        actual_initial_state = run.(Queue, :state, [:cola1])
        
        expected_initial_state = %PrimaryQueue{elements: [], max_size: 345, name: :cola1, subscribers: [], work_mode: :publish_subscribe}
        assert expected_initial_state == actual_initial_state
      end

      test "cannot create a queue that already exists" do    
        
      end

      test "primary and replica queue are created in different nodes" do    
        
      end

      test "if the node that contains the primary queue breaks, the primary queue is started in another node" do    
        
      end

      test "if the node that contains the primary queue breaks, the primary queue state comes from his replica" do    
        
      end

      test "what happen if we have a partition" do    
        
      end

      test "every node must have a udp and http server" do    
        
      end
end