defmodule App do
  use Application

  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies)

    children = [
      { Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] },
      App.HordeRegistry,
      { App.HordeSupervisor, [strategy: :one_for_one] },
      App.NodeObserver.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
