defmodule App do
  use Application
  require Logger

  def start(_type, _args) do
    udp_port = Enum.fetch!(System.argv, 0) |> String.to_integer
    Logger.info(inspect(udp_port))

    topologies = Application.get_env(:libcluster, :topologies)

    children = [
      { Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] },
      App.HordeRegistry,
      { App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] },
      App.NodeObserver.Supervisor,
      { UDPServerSupervisor, udp_port }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
