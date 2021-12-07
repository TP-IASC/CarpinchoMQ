:ok = LocalCluster.start()
Application.ensure_all_started(:carpincho_mq)
ExUnit.start()
