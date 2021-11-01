defmodule App.NodeObserver.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_) do
    children = [
      App.NodeObserver
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
