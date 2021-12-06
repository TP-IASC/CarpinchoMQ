defmodule HTTPServer do
  use Plug.Router

  import Plug.Conn

  plug Corsica,
    origins: "*",
    allow_headers: :all

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     json_decoder: Jason
  plug :dispatch


  get "/queues/:name/state" do
    atom_name = String.to_atom(name)
    state = Queue.state(atom_name)
    respond(conn, 200, state |> Poison.encode!)
  end

  get "/queues" do
    names = Utils.show_registry |> Enum.map( fn(x) -> x[:name] end) |> Enum.map(fn(x) -> Atom.to_string(x) end)
    names_without_replica = names |> Enum.filter(fn(n) -> !String.contains?(n, "_replica") end) |> Poison.encode!

    respond(conn, 200, names_without_replica)
  end


  @queue "name"
  @size "maxSize"
  @mode "workMode"

  post "/queues" do
    %{ @queue => name, @size => max_size, @mode => work_mode } = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    Producer.new_queue(atom_name, max_size, atom_mode)

    respond(conn, 200, "success!")
  end

  @payload "payload"

  post "/queues/:name/messages" do
    %{ @payload => payload } = conn.body_params
    atom_name = String.to_atom(name)
    Producer.push_message(atom_name, payload)

    respond(conn, 200, "success!")
  end


  match _ do
    respond(conn, 404, "resource not found")
  end


  def respond(conn, code, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, data)
  end

end