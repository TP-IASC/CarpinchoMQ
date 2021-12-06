defmodule UDPServerSupervisor do
  use Supervisor

  def start_link(port) do
    Supervisor.start_link(__MODULE__, port, name: __MODULE__)
  end


  def init(port) do
    children = [
      { UDPServer, port }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
