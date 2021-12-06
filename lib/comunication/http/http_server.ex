defmodule HTTPServer do
  use Plug.Router

  import Plug.Conn

  require OK
  require Logger

  plug Corsica,
    origins: "*",
    allow_headers: :all

  plug :match
  plug Plug.Parsers, parsers: [:json],
                     json_decoder: Jason
  plug :dispatch


  get "/queues/:name/state" do
    atom_name = String.to_atom(name)
    maybe_state = Queue.state(atom_name)
    handle_response(conn, maybe_state)
  end

  get "/queues" do
    names = Utils.show_registry |> Enum.map(fn(x) -> x[:name] end) |> Enum.map(fn(x) -> Atom.to_string(x) end)
    names_without_replica = names |> Enum.filter(fn(n) -> !String.contains?(n, "_replica") end)
    handle_response(conn, OK.success(names_without_replica))
  end


  @queue "name"
  @size "maxSize"
  @mode "workMode"

  post "/queues" do
    %{ @queue => name, @size => max_size, @mode => work_mode } = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    handle_post_response(conn, Producer.new_queue(atom_name, max_size, atom_mode))
  end

  @payload "payload"

  post "/queues/:name/messages" do
    %{ @payload => payload } = conn.body_params
    atom_name = String.to_atom(name)

    handle_post_response(conn, Producer.push_message(atom_name, payload))
  end


  match _ do
    respond(conn, 404, "resource not found")
  end

  def handle_post_response(conn, response) do
    maybe_result =  response |> OK.flat_map(fn _ -> OK.success("success!") end)
    handle_response(conn, maybe_result)
  end

  def handle_response(conn, maybe_data) do
    OK.try do
      data <- maybe_data
      json <- Poison.encode(data)
    after
      respond(conn, 200, json)
    rescue
      { _type, description } -> respond(conn, 404, description)
      _ -> respond(conn, 404, "resource not found")
    end
  end

  def respond(conn, code, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, data)
  end

  defp log_message(method, endpoint, message, logging_function),
    do: "[HTTP] [#{method}] [#{endpoint}] #{message}" |> logging_function.()

  defp debug(method, endpoint, message) do
    log_message(method, endpoint, message, &Logger.debug/1)
  end

  defp info(method, endpoint, message) do
    log_message(method, endpoint, message, &Logger.info/1)
  end

  defp warning(method, endpoint, message) do
    log_message(method, endpoint, message, &Logger.warning/1)
  end
end
