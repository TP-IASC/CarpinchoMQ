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


  defp primary_name() do
    Queue.primary_name(name())
  end
end
