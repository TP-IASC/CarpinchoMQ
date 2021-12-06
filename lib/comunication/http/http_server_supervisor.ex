defmodule HTTPServerSupervisor do
  use Supervisor

  def start_link(http_port) do
    Supervisor.start_link(__MODULE__, http_port, name: __MODULE__)
  end


  def init(http_port) do
    children = [
      {Plug.Cowboy, scheme: :http, plug:  HTTPServer, options: [port: http_port]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
