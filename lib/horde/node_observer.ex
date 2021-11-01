defmodule App.NodeObserver do
  use GenServer
  require Logger

  alias App.{HordeRegistry, HordeSupervisor}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    { :ok, state }
  end

  def handle_info({:nodedown, node, _node_type}, state) do
    Logger.info "Node down: #{node}"
    set_members(HordeRegistry)
    set_members(HordeSupervisor)
    { :noreply, state }
  end

  def handle_info({:nodeup, node, _node_type}, state) do
    Logger.info "Node up: #{node}"
    set_members(HordeRegistry)
    set_members(HordeSupervisor)
    { :noreply, state }
  end

  defp set_members(name) do
    members = Enum.map(Node.list([:this, :visible]), &{name, &1})
    :ok = Horde.Cluster.set_members(name, members)
  end
end
