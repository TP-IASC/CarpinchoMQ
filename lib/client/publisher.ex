defmodule Publisher do
  def new_queue(queue_name) do
    {:ok, pid1} = Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {PrimaryQueue, queue_name})
    replica_name = String.to_atom(Atom.to_string(queue_name) <> "_replica")
    {:ok, pid2} = Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {ReplicaQueue, replica_name})
    { pid1, pid2 }
  end

  def push_message(queue_name, message) do
    Queue.cast(queue_name, {:push, message})
  end
end
