defmodule Utils do
  def show_registry do
    specs = [{{:"$1", :"$2", :_ }, [], [%{ name: :"$1", pid: :"$2" }]}]
    Horde.Registry.select(App.HordeRegistry, specs)
  end

  def where_is(queue, nodes) do
    [node1, node2, node3] = nodes
    cond do
        get_processes(node1) |> queue_exists?(queue) -> node1
        get_processes(node2) |> queue_exists?(queue) -> node2
        get_processes(node3) |> queue_exists?(queue) -> node3
    end
  end

  def get_processes(node), do: :rpc.call(node, Process, :list, [])

  def queue_exists?(processes, queue) do
    if processes == {:badrpc, :nodedown} do false else Enum.member?(processes, queue) end
  end
end
