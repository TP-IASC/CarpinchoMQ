defmodule AvoidReplica do
  @behaviour Horde.DistributionStrategy
  require Logger

  def has_quorum?(_members), do: true

  def choose_node(identifier, members) do
    IO.inspect identifier
    IO.inspect members
    Horde.UniformDistribution.choose_node(identifier, members)
  end
end
