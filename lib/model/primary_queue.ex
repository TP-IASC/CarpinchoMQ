defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(name) do
    replica = replica_name()
    queue = if Queue.alive?(replica), do: Queue.queue(replica), else: []
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)
    { :ok, queue }
  end


  def handle_cast({:push, payload}, queue) do
    new_message = create_message(payload)

    replica_name()
    |> Queue.cast({ :push, new_message })

    { :noreply, [new_message | queue] }
  end


  defp replica_name(),
    do: String.to_atom(Atom.to_string(name()) <> "_replica")
end
