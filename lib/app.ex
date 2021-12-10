defmodule App do
  use Application
  require Logger

  def start(_type, _args) do
    extra_childs = case Mix.env do
      :test -> []
      _ ->
        http_port = Enum.fetch!(System.argv, 0) |> String.to_integer
        udp_port = Enum.fetch!(System.argv, 1) |> String.to_integer
        [
          { HTTPServerSupervisor, http_port },
          { UDPServerSupervisor, udp_port }
        ]
    end

    topologies = Application.get_env(:libcluster, :topologies)

    children = [
      { Cluster.Supervisor, [topologies, [name: App.ClusterSupervisor]] },
      App.HordeRegistry,
      { App.HordeSupervisor, [strategy: :one_for_one, distribution_strategy: AvoidReplica, process_redistribution: :active] },
      App.NodeObserver.Supervisor,
    ] ++ extra_childs

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
