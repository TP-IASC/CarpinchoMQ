defmodule Queue do
  defmacro __using__(_opts) do
    quote do
      use GenServer
      import Queue
      require Logger

      def start_link(name) when is_atom(name) do
        GenServer.start_link(__MODULE__, name, name: via_tuple(name))
      end

      def handle_info({:EXIT, _from, {:name_conflict, {name, _value}, _registry_name, winning_pid}}, state) do
        Logger.info "Resolving conflicts in #{name}"
        GenServer.cast(winning_pid, {:horde, :resolve_conflict, state})
        { :stop, :normal, state }
      end

      # Por ahi conviene que sea call para que el proceso que envia la request tenga una confirmacion de recepcion
      def handle_cast({:horde, :resolve_conflict, remote_queue}, queue) do
        { :noreply, merge_queues(queue, remote_queue) }
      end

      def handle_call(:get, _from, queue) do
        { :reply, queue, queue }
      end

      def name,
        do: Horde.Registry.keys(App.HordeRegistry, self()) |> List.first()
    end
  end

  def via_tuple(queue_name),
    do: { :via, Horde.Registry, {App.HordeRegistry, queue_name} }

  def whereis(queue_name),
    do: GenServer.whereis(via_tuple(queue_name))

  def merge_queues(queue1, queue2) do
    Enum.concat(queue1, queue2)
      |> Enum.sort_by(fn msg -> msg.timestamp end, &DateTime.compare(&1, &2) != :lt)
      |> Enum.dedup
  end

  def create_message(payload) do
    now = DateTime.utc_now()
    id = :crypto.hash(:md5, :erlang.term_to_binary([now, payload]))
      |> Base.encode16
      |> String.to_atom

    %{ id: id, timestamp: now, payload: payload }
  end

  def alive?(name), do: whereis(name) != nil

  def queue(name) do
    call(name, :get)
  end

  def cast(queue_name, request) do
    via_tuple(queue_name)
    |> GenServer.cast(request)
  end

  def call(queue_name, request) do
    via_tuple(queue_name)
    |> GenServer.call(request)
  end
end
