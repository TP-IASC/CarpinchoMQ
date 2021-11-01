defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(name) do
    primary = primary_name()
    queue = if Queue.alive?(primary), do: Queue.queue(primary), else: []
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)
    { :ok, queue }
  end


  def handle_cast({:push, message}, queue) do
    { :noreply, [message | queue] }
  end


  defp sufix, do: "_replica"

  defp primary_name() do
    Atom.to_string(name())
    |> String.slice(0..-String.length(sufix())-1)
    |> String.to_atom
  end
end
