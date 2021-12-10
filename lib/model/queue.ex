defmodule Queue do
  require Logger
  require OK

  defstruct [
    :name,
    :max_size,
    :work_mode,
    :queue_mode,
    elements: [],
    subscribers: [],
    next_subscriber_to_send: 0
  ]

  @type t() :: %__MODULE__{
    name: atom(),
    max_size: integer(),
    work_mode: WorkMode.t(),
    queue_mode: any(),
    elements: list(),
    next_subscriber_to_send: integer()
  }

  defmacro __using__(_opts) do
    quote do
      use GenServer
      import Queue
      require Logger
      require OK

      def start_link([name, max_size, work_mode, queue_mode]) when is_atom(name) do
        default_state = %Queue{name: name, max_size: max_size, work_mode: work_mode, queue_mode: queue_mode}
        GenServer.start_link(__MODULE__, default_state, name: via_tuple(name))
      end

      def handle_info({:EXIT, _from, {:name_conflict, {_name, _value}, _registry_name, winning_pid}}, state) do
        GenServer.cast(winning_pid, {:horde, :resolve_conflict, state})
        {:stop, :normal, state}
      end

      # Por ahi conviene que sea call para que el proceso que envia la request tenga una confirmacion de recepcion
      def handle_cast({:horde, :resolve_conflict, remote_state}, state) do
        info(state.name, "resolving conflicts")
        new_state = Map.put(state, :elements, Queue.merge_queues(state.elements, remote_state.elements))
        {:noreply, new_state}
      end

      def handle_call(:get, _from, state) do
        {:reply, state, state}
      end

      defp add_new_element(state, new_message) do
        new_element = %{message: new_message, consumers_that_did_not_ack: [], number_of_attempts: 0}
        Map.put(state, :elements, [new_element | state.elements])
      end

      defp update_next_subscriber(state, next_subscriber_to_send) do
        Map.put(state, :next_subscriber_to_send, next_subscriber_to_send)
      end

      defp delete_element(state, element) do
        Map.put(state, :elements, List.delete(state.elements, element))
      end

      defp update_specific_element(state, message_id, update_element) do
        Map.put(
          state,
          :elements,
          Enum.map(
            state.elements,
            fn element ->
              if element.message.id == message_id do
                update_element.(element)
              else
                element
              end
            end
          )
        )
      end

      defp add_subscriber(state, subscriber) do
        Map.put(state, :subscribers, state.subscribers ++ [subscriber])
      end

      defp remove_subscribers(state, subscribers) do
        Map.put(state, :subscribers, state.subscribers -- subscribers)
      end

      defp update_consumers_that_did_not_ack(element, consumers) do
        Map.put(element, :consumers_that_did_not_ack, element.consumers_that_did_not_ack -- consumers)
      end

      defp init_sent_element_props(element, subscribers) do
        element
        |> Map.put(:consumers_that_did_not_ack, subscribers)
        |> increase_number_of_attempts
      end

      defp increase_number_of_attempts(element),
           do: Map.put(element, :number_of_attempts, element.number_of_attempts + 1)

      defp delete_subscribers(state, subscribers_to_delete) do
        state
        |> remove_subscribers(subscribers_to_delete)
        |> delete_subscribers_from_all_elements(subscribers_to_delete)
        |> delete_elements_that_dont_require_acks_anymore
      end

      defp delete_subscribers_from_all_elements(state, subscribers_to_delete) do
        Map.put(
          state,
          :elements,
          Enum.map(
            state.elements,
            fn element ->
              update_consumers_that_did_not_ack(element, subscribers_to_delete)
            end
          )
        )
      end

      defp delete_elements_that_dont_require_acks_anymore(state) do
        Map.put(state, :elements, Enum.reject(state.elements, fn element -> got_all_acks?(element) end))
      end

      defp got_all_acks?(element), do: Enum.empty?(element.consumers_that_did_not_ack)
    end
  end

  def via_tuple(queue_name), do: {:via, Horde.Registry, {App.HordeRegistry, queue_name}}

  def whereis(queue_name), do: GenServer.whereis(via_tuple(queue_name))

  def merge_queues(queue1, queue2) do
    Enum.concat(queue1, queue2)
      |> Enum.sort_by(fn element -> element.message.timestamp end, &DateTime.compare(&1, &2) != :lt)
      |> Enum.dedup
  end

  def create_message(payload) do
    now = DateTime.utc_now()
    id = :crypto.hash(:md5, :erlang.term_to_binary([now, payload]))
         |> Base.encode16
         |> String.to_atom

    %{id: id, timestamp: now, payload: payload}
  end

  defp replica_sufix, do: "_replica"

  def replica_name(queue_name) when is_atom(queue_name),
      do: Atom.to_string(queue_name) <> replica_sufix()
          |> String.to_atom

  def primary_name(replica_name) when is_atom(replica_name),
      do: Atom.to_string(replica_name)
          |> String.slice(0..-String.length(replica_sufix()) - 1)
          |> String.to_atom

  def valid_name?(queue_name), do: not String.ends_with?(Atom.to_string(queue_name), replica_sufix())

  def alive?(name), do: whereis(name) != nil

  def state(name) do
    call(name, :get)
  end

  def cast(queue_name, request) do
    via_tuple(queue_name)
    |> GenServer.cast(request)
  end

  def call(queue_name, request) do
    OK.for do
      _ <- check_alive(queue_name)
      result <- via_tuple(queue_name)
                |> GenServer.call(request)
                |> OK.wrap
    after
      result
    end
  end

  @spec new(queue_name :: atom(), max_size :: integer(), work_mode :: WorkMode.t(), queue_mode :: any()) :: {:ok, any()} | {:error, any()}
  def new(queue_name, max_size, work_mode, queue_mode) do
    OK.for do
      _ <- check_name(queue_name)
      {primary_name, replica_name} <- complete_check(queue_name, &check_not_alive/1)
      primary_pid <- Horde.DynamicSupervisor.start_child(
        App.HordeSupervisor,
        {PrimaryQueue, [primary_name, max_size, work_mode, queue_mode]}
      )
      replica_pid <- Horde.DynamicSupervisor.start_child(
        App.HordeSupervisor,
        {ReplicaQueue, [replica_name, max_size, work_mode, queue_mode]}
      )
    after
      {primary_pid, replica_pid}
    end
  end

  def delete(queue_name) do
    OK.for do
      {primary_name, replica_name} <- complete_check(queue_name, &check_alive/1)
      GenServer.cast(via_tuple(primary_name), :notify_shutdown)
      Horde.DynamicSupervisor.terminate_child(App.HordeSupervisor, whereis(primary_name))
      Horde.DynamicSupervisor.terminate_child(App.HordeSupervisor, whereis(replica_name))
    after
      :deleted
    end
  end

  defp check_name(queue_name),
       do: OK.check({:ok, queue_name}, &(Queue.valid_name?(&1)), Errors.name_not_allowed(queue_name))

  defp check_not_alive(queue_name),
       do: OK.check({:ok, queue_name}, &(!Queue.alive?(&1)), Errors.queue_already_exists(queue_name))

  def check_alive(queue_name),
      do: OK.check({:ok, queue_name}, &(Queue.alive?(&1)), Errors.queue_not_found(queue_name))

  defp complete_check(queue_name, check) do
    OK.for do
      a <- check.(queue_name)
      b <- check.(replica_name(queue_name))
    after
      {a, b}
    end
  end

  def log_message(queue_name, message, logging_function),
      do: "[QUEUE] [#{Atom.to_string(queue_name)}] #{message}"
          |> logging_function.()

  def debug(queue_name, message) do
    log_message(queue_name, message, &Logger.debug/1)
  end

  def info(queue_name, message) do
    log_message(queue_name, message, &Logger.info/1)
  end

  def warning(queue_name, message) do
    log_message(queue_name, message, &Logger.warning/1)
  end
end
