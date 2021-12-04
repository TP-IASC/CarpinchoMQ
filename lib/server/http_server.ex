defmodule HTTPServer do
  use Plug.Router
  import Plug.Conn
#  import Queue
  import Logger


  plug :match
  plug Plug.Parsers, parsers: [:json],
                     json_decoder: Jason
  plug :dispatch



  @queue "queue_name"


  get "/queue/state" do
    conn = fetch_query_params(conn)
    %{ @queue => name} = conn.params
    atom_name = String.to_atom(name)

    state_json = Queue.state(atom_name) |> Poison.encode!

    send_resp(conn, 200, state_json)
  end

  @size "max_size"
  @mode "work_mode"

  post "/queue/new" do

    %{ @queue => name, @size => max_size, @mode => work_mode} = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    Producer.new_queue(atom_name, max_size, atom_mode)

    send_resp(conn, 200, "Success!")
  end

  @message "message"

  post "/queue/message" do

    %{ @queue => name, @message => message} = conn.body_params
    atom_name = String.to_atom(name)

    Producer.push_message(atom_name, message)

    send_resp(conn, 200, "Success!")
  end



 # match _ do
  #  send_resp(conn, 404, "oops")
  #end
end
