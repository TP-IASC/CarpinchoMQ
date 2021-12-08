defmodule UDPServer do
  use GenServer
  require Logger
  require OK

  def start_link(port \\ 2052) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end


  def init(port) do
    info("started server on port #{inspect(port)}")
    :gen_udp.open(port, [:binary, active: true])
  end

  def handle_cast({:send_removed, queue_name, reason, consumer}, socket) do
    UDPServer.send(queue_name, "removed", reason, consumer)
    { :noreply, socket }
  end

  def handle_cast({:send_message, queue_name, message, consumer}, socket) do
    UDPServer.send(queue_name, "message", message, consumer)
    { :noreply, socket }
  end

  def handle_cast({:send, queue_name, method, data, consumer}, socket) do
    message = %{
      "queueName" => Atom.to_string(queue_name),
      "method" => method,
      "data" => data
    }

    OK.try do
      json <- Jason.encode(message)
      address <- consumer.address |> to_charlist |> :inet.parse_address()
    after
      debug("sending #{inspect(message)} from #{queue_name} to #{inspect(consumer)}")
      :gen_udp.send(socket, address, consumer.port, json)
    rescue
      reason ->
        warning("message send #{inspect(message)} failed, reason: #{reason}")
    end

    { :noreply, socket }
  end

  def handle_info({:udp, _socket, address, _port, data}, socket) do
    case Jason.decode(data) do
      { :ok, %{ "port" => listeningPort, "data" => %{ "method" => method, "body" => body } } } ->
        if valid_port?(listeningPort) do
         consumer = new_consumer(address, listeningPort)
         handle_packet(method, body, consumer)
        else
          warning("received invalid listening port in #{inspect(data)}")
        end

      _ -> handle_parse_error(data)
    end

    { :noreply, socket }
  end

  def send(queue_name, method, data, consumer) do
    GenServer.cast(UDPServer, { :send, queue_name, method, data, consumer })
  end

  def send_message(queue_name, message, consumer) do
    GenServer.cast(UDPServer, { :send_message, queue_name, message, consumer })
  end

  def send_remove_notification(queue_name, reason, consumer) do
    GenServer.cast(UDPServer, { :send_removed, queue_name, reason, consumer })
  end

  defp handle_packet("subscribe", %{ "queueName" => queue_name }, consumer) do
    info("subscription message from #{inspect(consumer)} to #{queue_name}")
    Consumer.subscribe(String.to_atom(queue_name), consumer)
  end

  defp handle_packet("unsubscribe", %{ "queueName" => queue_name }, consumer) do
    info("unsubscription message from from #{inspect(consumer)} to #{queue_name}")
    Consumer.unsubscribe(String.to_atom(queue_name), consumer)
  end

  defp handle_packet("ack", %{ "queueName" => queue_name, "messageId" => message_id }, consumer) do
    info("received ack message from #{inspect(consumer)} to #{queue_name}")
    Consumer.ack(String.to_atom(queue_name), String.to_atom(message_id), consumer)
  end

  defp handle_packet(method, body, consumer) do
    debug("[#{String.upcase(method)}] could not resolve method for body: #{inspect(body)} (#{consumer_string(consumer)})")
  end

  defp consumer_string(consumer) do
    "#{consumer.address}:#{consumer.port}"
  end

  defp handle_parse_error(data) do
    debug("could not parse message: #{inspect(data)}")
  end

  defp log_message(message, logging_function),
    do: "[UDP] #{message}" |> logging_function.()

  defp debug(message) do
    log_message(message, &Logger.debug/1)
  end

  defp info(message) do
    log_message(message, &Logger.info/1)
  end

  defp warning(message) do
    log_message(message, &Logger.warning/1)
  end

  defp new_consumer(address, port) do
    %{
      address: address |> :inet_parse.ntoa |> to_string(),
      port: port
    }
  end

  defp valid_port?(port), do: is_integer(port)
end
