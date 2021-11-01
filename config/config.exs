import Config


config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Gossip,
    ]
  ]
