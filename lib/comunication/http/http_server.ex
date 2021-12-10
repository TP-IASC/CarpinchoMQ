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
    maybe_state = OK.for do
      state <- Queue.state(atom_name)
      pretty = Map.put(state, :work_mode, state.work_mode.to_atom())
    after
      pretty
    end
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

    %{ @queue => name, @size => max_size_str, @mode => work_mode } = conn.body_params
    atom_name = String.to_atom(name)
    atom_mode = String.to_atom(work_mode)

    creation_result = OK.for do
      max_size <- cast_to_integer("maxSize", max_size_str)
      mode <- check_work_mode(atom_mode)
      result <- Producer.new_queue(atom_name, max_size, mode)
    after
      result
    end

    handle_response_with_success(conn, creation_result)
  end

  @payload "payload"

  post "/queues/:name/messages" do
    endpoint_info(conn)
    %{ @payload => payload } = conn.body_params
    atom_name = String.to_atom(name)

    handle_response_with_success(conn, Producer.push_message(atom_name, payload))
  end


  delete "/queues/:name" do
    endpoint_info(conn)
    queue_name = String.to_atom(name)
    handle_response_with_success(conn, Producer.delete_queue(queue_name))
  end


  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: _kind, reason: reason, stack: stack}) do
    endpoint_warning(conn)
    warning("Unexpected error #{inspect({reason, stack})}")
    respond(conn, conn.status, "Unexpected error")
  end

  def handle_response_with_success(conn, response) do
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

  defp cast_to_integer(field, value) do
    case Integer.parse(value) do
      :error -> OK.failure(Errors.type_error(field, "integer", value))
      { integer, _ } -> OK.success(integer)
    end
  end

  defp check_work_mode(work_mode) do
    work_modes_mappings = [
      pub_sub: PubSub,
      work_queue: WorkQueue
    ]

    OK.check({:ok, work_modes_mappings[work_mode]}, &(&1 != nil), Errors.invalid_work_mode(work_mode))
  end

  defp endpoint_log(conn, logging_function),
    do: log_message("#{String.upcase(conn.method)} #{conn.request_path} #{inspect(conn.body_params)}", logging_function)

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
