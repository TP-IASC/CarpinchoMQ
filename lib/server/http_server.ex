defmodule HTTPServer do
  use Plug.Router
  import Plug.Conn

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     json_decoder: Jason
  plug :dispatch


  @queue "queue_name"


  get "/queue/:name/state" do

    atom_name = String.to_atom(name)
    state = Queue.state(atom_name)

    send_resp(conn, 200, state |> Poison.encode!)
  end

  get "/queues" do

    names = Utils.show_registry |> Enum.map( fn(x) -> x[:name] end) |> Enum.map(fn(x) -> Atom.to_string(x) end)
    names_without_replica = names |> Enum.filter(fn(n) -> !String.contains?(n, "_replica") end) |> Poison.encode!

    send_resp(conn, 200, names_without_replica)
  end


  @size "max_size"
  @mode "work_mode"

  post "/queue" do

    %{ @queue => name, @size => max_size, @mode => work_mode} = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    Producer.new_queue(atom_name, max_size, atom_mode)

    send_resp(conn, 200, "Success!")
  end

  @message "message"

  post "/queue/state/messages" do

    %{ @queue => name, @message => message} = conn.body_params
    atom_name = String.to_atom(name)

    Producer.push_message(atom_name, message)

    send_resp(conn, 200, "Success!")
  end

end
