defmodule AvoidReplica do
  @behaviour Horde.DistributionStrategy
  require Logger

  def has_quorum?(_members), do: true

  def choose_node(child_spec, members) do
    valid_members = case child_spec.start do
      _ when length(members) == 1 ->
        warning("only one node available, primary and replica queues will be started on the same node, please connect to another node")
        members
      {ReplicaQueue, :start_link, [[name|_]]} -> avoid_primary(members, name)
      {PrimaryQueue, :start_link, [[name|_]]} -> avoid_replica(members, name)
      _   -> members
    end

    Horde.UniformDistribution.choose_node(child_spec, valid_members)
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

  defp warning(message) do
    Logger.warning("[DISTRIBUTION_STRATEGY] #{message}")
  end
end
