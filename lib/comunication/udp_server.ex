defmodule UDPServer do
  use GenServer
  require Logger

  def start_link(port \\ 2052) do
    GenServer.start_link(__MODULE__, port)
  end


  def init(port) do
    Logger.info("starting UDP server on port #{inspect(port)}")
    :gen_udp.open(port, [:binary, active: true])
  end

  def handle_info({:udp, _socket, address, port, data}, socket) do
    case Jason.decode(data) do
      { :ok, %{ "method" => method, "data" => data } } ->
        handle_packet(method, data, address, port)
      _ -> Logger.debug("udp server could not parse message: #{inspect(data)}")
    end

    { :noreply, socket }
  end

  defp handle_packet("subscribe", %{ "queueName" => queue_name }, address, port) do
    Consumer.subscribe(queue_name, %{ address: address, port: port })
  end

  defp handle_packet("unsubscribe", %{ "queueName" => queue_name }, address, port) do
    Consumer.unsubscribe(queue_name, %{ address: address, port: port })
  end

  defp handle_packet("ack", %{ "queueName" => queue_name, "messageId" => message_id }, _address, _port) do
    Logger.info "TODO ACK #{message_id} ON QUEUE #{queue_name}"
  end

  defp handle_packet(method, data, address, port) do
    message = %{
      "method" => method,
      "data" => data,
      "from" => inspect(address) <> ":" <> inspect(port)
    }
    Logger.debug("udp server could not resolve method: #{inspect(message)}")
  end
end
