defmodule App do
  use Application

  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies)
    http_port = Enum.fetch!(System.argv, 0) |> String.to_integer
    children = [
      { Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] },
      App.HordeRegistry,
      { App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] },
      App.NodeObserver.Supervisor,
      {Plug.Cowboy, scheme: :http, plug:  HTTPServer, options: [port: http_port]}

    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
