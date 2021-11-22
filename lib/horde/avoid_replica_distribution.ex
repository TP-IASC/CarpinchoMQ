defmodule AvoidReplica do
  @behaviour Horde.DistributionStrategy
  require Logger

  def has_quorum?(_members), do: true

  def choose_node(identifier, child_spec, members) do
    filtered_members = case child_spec.start do
      {ReplicaQueue, :start_link, [replica_name]} when length(members) > 1 ->
        avoid_primary(members, replica_name)
      {PrimaryQueue, :start_link, [queue_name]} when length(members) > 1 ->
        avoid_replica(members, queue_name)
      _   -> members
    end

    Horde.UniformDistribution.choose_node(identifier, child_spec, filtered_members)
  end


  def avoid_primary(members, replica_name) do
    avoid(members, Queue.primary_name(replica_name))
  end

  def avoid_replica(members, queue_name) do
    avoid(members, Queue.replica_name(queue_name))
  end

  def avoid(members, other_queue) do
    other_pid = Queue.whereis(other_queue)
    case other_pid do
      nil -> members
      _   -> Enum.filter(members, fn %{name: {_, node}} -> node != :erlang.node(other_pid) end)
    end
  end
end
