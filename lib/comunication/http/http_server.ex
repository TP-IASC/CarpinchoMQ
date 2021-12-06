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
    endpoint_info("GET", "/queues/#{name}/state")
    atom_name = String.to_atom(name)
    maybe_state = Queue.state(atom_name)
    handle_response(conn, maybe_state)
  end

  get "/queues" do
    endpoint_info("GET", "/queues")
    names = Utils.show_registry |> Enum.map(fn(x) -> x[:name] end) |> Enum.map(fn(x) -> Atom.to_string(x) end)
    names_without_replica = names |> Enum.filter(fn(n) -> !String.contains?(n, "_replica") end)
    handle_response(conn, OK.success(names_without_replica))
  end


  @queue "name"
  @size "maxSize"
  @mode "workMode"

  post "/queues" do
    endpoint_info("POST", "/queues", conn.body_params)
    %{ @queue => name, @size => max_size, @mode => work_mode } = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    handle_post_response(conn, Producer.new_queue(atom_name, max_size, atom_mode))
  end

  @payload "payload"

  post "/queues/:name/messages" do
    endpoint_info("POST", "/queues/#{name}/messages", conn.body_params)
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
      error_reason -> Errors.json(error_reason)
    end
  end

  def respond(conn, code, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, data)
  end

  defp endpoint_log(method, endpoint, body, logging_function),
    do: "[HTTP] #{method} #{endpoint} #{inspect(body)}" |> logging_function.()

  defp endpoint_info(method, endpoint, body \\ %{}),
    do: endpoint_log(method, endpoint, body, &Logger.info/1)

#  defp log_message(message, logging_function),
#    do: "[HTTP] #{message}" |> logging_function.()
#
#  defp info(message),
#    do: log_message(message, &Logger.info/1)

#  defp debug(message),
#    do: log_message(message, &Logger.debug/1)
end