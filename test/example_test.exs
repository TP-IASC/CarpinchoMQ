defmodule ExampleTest do
  use ExUnit.Case
  require Logger

  test "if the node that contains the primary queue breaks, the primary queue is started in another node" do
    {:ok, _} = Application.ensure_all_started(:carpincho_mq)
    nodes = LocalCluster.start_nodes("my-cluster", 3, files: [__ENV__.file])

    [node1, node2, node3] = nodes

    Process.sleep(10000)

    {:ok, {primary_pid, replica_pid}} = :rpc.call(node1, Queue, :new, [:cola1, 345, :publish_subscribe])

    Process.sleep(10000)

    old_node = where_is(primary_pid, nodes)
    LocalCluster.stop_nodes([old_node])

    Process.sleep(10000)

    alive_node = Enum.find(nodes, fn node -> :rpc.call(node, Node, :alive?, []) == true end)

    new_primary_pid = :rpc.call(alive_node, Queue, :whereis, [:cola1])
    new_node = where_is(new_primary_pid, nodes)

    Logger.info "New Node #{inspect new_node}"
    Logger.info "Old Node #{inspect old_node}"

    assert old_node != new_node
  end

  defp where_is(queue, nodes) do
    [node1, node2, node3] = nodes
    cond do
      get_processes(node1) |> queue_exists?(queue) -> node1
      get_processes(node2) |> queue_exists?(queue) -> node2
      get_processes(node3) |> queue_exists?(queue) -> node3
      Process.list |> queue_exists?(queue) -> node
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