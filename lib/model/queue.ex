defmodule Queue do
  require Logger
  require OK

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import Queue
      require Logger
      require OK

      defstruct [:name,
                 :max_size,
                 :work_mode,
                 elements: [],
                 subscribers: []]

      def start_link([name, max_size, work_mode]) when is_atom(name) do
        default_state = %__MODULE__{ name: name, max_size: max_size, work_mode: work_mode }
        GenServer.start_link(__MODULE__, default_state, name: via_tuple(name))
      end

      def handle_info({:EXIT, _from, {:name_conflict, {_name, _value}, _registry_name, winning_pid}}, state) do
        GenServer.cast(winning_pid, {:horde, :resolve_conflict, state})
        { :stop, :normal, state }
      end

      # Por ahi conviene que sea call para que el proceso que envia la request tenga una confirmacion de recepcion
      def handle_cast({:horde, :resolve_conflict, remote_state}, state) do
        info(state.name, "resolving conflicts")
        new_state = Map.put(state, :elements, Queue.merge_queues(state.elements, remote_state.elements))
        { :noreply, new_state }
      end

      def handle_call(:get, _from, state) do
        { :reply, state, state }
      end

      defp add_new_element(state, new_message) do
        new_element = %{message: new_message, consumers_that_did_not_ack: [], number_of_attempts: 0}
        Map.put(state, :elements, [new_element|state.elements])
      end

      defp delete_element(state, element) do
        Map.put(state, :elements, List.delete(state.elements, element))
      end

      defp update_specific_element(state, message_id, update_element) do
        Map.put(state, :elements, Enum.map(state.elements, fn element ->
          if element.message.id == message_id do update_element.(element) else element end
        end))
      end

      defp add_subscriber(state, subscriber) do
        Map.put(state, :subscribers, [subscriber|state.subscribers])
      end

      defp remove_subscriber(state, subscriber) do
        Map.put(state, :subscribers, List.delete(state.subscribers, subscriber))
      end

      defp update_consumers_that_did_not_ack(element, consumer_pid) do
        Map.put(element, :consumers_that_did_not_ack, List.delete(element.consumers_that_did_not_ack, consumer_pid))
      end

      defp init_element(element, subscribers) do
        element
          |> Map.put(:consumers_that_did_not_ack, subscribers)
          |> increase_number_of_attempts
      end

      defp increase_number_of_attempts(element),
        do: Map.put(element, :number_of_attempts, element.number_of_attempts + 1)

      defp log_message(queue_name, message),
        do: "[QUEUE] [#{Atom.to_string(queue_name)}] #{message}"

      defp debug(queue_name, message) do
        log_message(queue_name, message) |> Logger.debug
      end

      defp info(queue_name, message) do
        log_message(queue_name, message) |> Logger.info
      end

      defp warning(queue_name, message) do
        log_message(queue_name, message) |> Logger.warning
      end
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

  defp replica_sufix, do: "_replica"

  def replica_name(queue_name) when is_atom(queue_name),
    do: Atom.to_string(queue_name) <> replica_sufix() |> String.to_atom

  def primary_name(replica_name) when is_atom(replica_name),
    do: Atom.to_string(replica_name)
        |> String.slice(0..-String.length(replica_sufix())-1)
        |> String.to_atom

  def valid_name?(queue_name),
    do: not String.ends_with?(Atom.to_string(queue_name), replica_sufix())

  def alive?(name), do: whereis(name) != nil

  def state(name) do
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

  def all do

   elem = Supervisor.which_children(App.HordeSupervisor) |> Enum.map(fn {_, x,_,_} -> x end) |> List.first
   IO.inspect(elem)
      Process.info(elem)
  end
  def new(queue_name, max_size, work_mode) do
    OK.for do
      _ <- check_name(queue_name)
      { primary_name, replica_name } <- complete_check(queue_name, &check_not_alive/1)
      primary_pid <- Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {PrimaryQueue, [primary_name, max_size, work_mode]})
      replica_pid <- Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {ReplicaQueue, [replica_name, max_size, work_mode]})
    after
      { primary_pid, replica_pid }
    end
  end


  def delete(queue_name) do
    OK.for do
      { primary_name, replica_name } <- complete_check(queue_name, &check_alive/1)
      Horde.DynamicSupervisor.terminate_child(App.HordeSupervisor, whereis(primary_name))
      Horde.DynamicSupervisor.terminate_child(App.HordeSupervisor, whereis(replica_name))
    after
      :deleted
    end
  end

  defp check_name(queue_name),
    do: OK.check({:ok, queue_name}, &(Queue.valid_name?(&1)), {:name_not_allowed, "Queue name #{inspect(queue_name)} is not allowed"})

  defp check_not_alive(queue_name),
    do: OK.check({:ok, queue_name}, &(!Queue.alive?(&1)), {:queue_already_exists, "A queue named #{inspect(queue_name)} already exists"})

  defp check_alive(queue_name),
    do: OK.check({:ok, queue_name}, &(Queue.alive?(&1)), {:queue_not_found, "A queue named #{inspect(queue_name)} does not exist"})

  defp complete_check(queue_name, check) do
    OK.for do
      a <- check.(queue_name)
      b <- check.(replica_name(queue_name))
    after
      { a, b }
    end
  end
end
