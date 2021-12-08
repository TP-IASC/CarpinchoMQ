IO.puts("I'm here! Sleeping for 2 seconds")

Process.sleep 2_000 # waiting for the other node

nodes = MapSet.new([:a, :b])
other_node =
	nodes
	|> MapSet.delete(Node.self())
	|> MapSet.to_list()
	|> List.first()
	|> IO.inspect(label: "[self is #{inspect(Node.self)}]")

Node.connect(other_node) |> IO.inspect(label: "connect (from #{inspect(Node.self)}")

Process.sleep 2_000

Node.list() |> IO.inspect(label: "nodes")


Enum.each 1..5, fn _ ->

	Node.ping(other_node)
	|> IO.inspect(label: "ping #{inspect(other_node)}")
	Process.sleep(1_000)
end
