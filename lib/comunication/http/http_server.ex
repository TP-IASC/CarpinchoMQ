defmodule HTTPServer do
  use Plug.Router
  use Plug.ErrorHandler

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
    endpoint_info(conn)
    atom_name = String.to_atom(name)
    maybe_state = Queue.state(atom_name)
    handle_response(conn, maybe_state)
  end

  get "/queues" do
    endpoint_info(conn)
    names = Utils.show_registry |> Enum.map(fn(x) -> x[:name] end) |> Enum.map(fn(x) -> Atom.to_string(x) end)
    names_without_replica = names |> Enum.filter(fn(n) -> !String.contains?(n, "_replica") end)
    handle_response(conn, OK.success(names_without_replica))
  end


  @queue "name"
  @size "maxSize"
  @mode "workMode"

  post "/queues" do
    endpoint_info(conn)
    %{ @queue => name, @size => max_size, @mode => work_mode } = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    handle_post_response(conn, Producer.new_queue(atom_name, max_size, atom_mode))
  end

  @payload "payload"

  post "/queues/:name/messages" do
    endpoint_info(conn)
    %{ @payload => payload } = conn.body_params
    atom_name = String.to_atom(name)

    handle_post_response(conn, Producer.push_message(atom_name, payload))
  end


  delete "/queues/:name" do
    endpoint_info(conn)
    queue_name = String.to_atom(name)
    handle_post_response(conn, Producer.delete_queue(queue_name))
  end


  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: _kind, reason: reason, stack: stack}) do
    endpoint_warning(conn)
    warning("Unexpected error #{inspect({reason, stack})}")
    respond(conn, conn.status, "Unexpected error")
  end

  def handle_post_response(conn, response) do
    maybe_result =  response |> OK.flat_map(fn _ -> OK.success("success!") end)
    handle_response(conn, maybe_result)
  end

  def handle_response(conn, maybe_data) do
    { code, data } = OK.try do
      data <- maybe_data
      json <- Poison.encode(data)
    after
      { 200, json }
    rescue
      { type, code, description } -> { code, Jason.encode!(%{"type" => type, "description" => description}) }
      _ -> { 500, "Unexpected error" }
    end

    respond(conn, code, data)
  end

  def respond(conn, code, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(code, data)
  end

  defp endpoint_log(conn, logging_function),
    do: "[HTTP] #{String.upcase(conn.method)} #{conn.request_path} #{inspect(conn.body_params)}" |> logging_function.()

  defp endpoint_info(conn),
    do: endpoint_log(conn, &Logger.info/1)

  defp endpoint_warning(conn),
    do: endpoint_log(conn, &Logger.warning/1)

  defp log_message(message, logging_function),
    do: "[HTTP] #{message}" |> logging_function.()
#
#  defp info(message),
#    do: log_message(message, &Logger.info/1)

#  defp debug(message),
#    do: log_message(message, &Logger.debug/1)

  defp warning(message),
    do: log_message(message, &Logger.warning/1)
end
