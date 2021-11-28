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

      # @type element :: %{ message, consumidores_que_no_respondieron: [pid] }
      # TODO: modificar el state para que los elementos tengan esa forma (cada elemento guarda el mensaje y los consumidores que todavia no respondieron)

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
        Logger.info "Resolving conflicts in #{state.name}..."
        new_state = Map.put(state, :elements, Queue.merge_queues(state.elements, remote_state.elements))
        { :noreply, new_state }
      end

      def handle_call(:get, _from, state) do
        { :reply, state, state }
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

  def replica_name(queue_name) when is_atom(queue_name),
    do: Atom.to_string(queue_name) <> "_replica" |> String.to_atom

  def primary_name(replica_name) when is_atom(replica_name),
    do: Atom.to_string(replica_name)
        |> String.slice(0..-String.length("_replica")-1)
        |> String.to_atom

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

  def new(queue_name, max_size, work_mode) do
    OK.for do
      primary_name <- check_queue(queue_name)
      replica_name <- check_queue(Queue.replica_name(queue_name))
      primary_pid <- Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {PrimaryQueue, [primary_name, max_size, work_mode]})
      replica_pid <- Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {ReplicaQueue, [replica_name, max_size, work_mode]})
    after
      { primary_pid, replica_pid }
    end
  end

  defp check_queue(queue_name),
    do: OK.check({:ok, queue_name}, &(!Queue.alive?(&1)), {:queue_already_exists, "A queue named #{inspect(queue_name)} already exists"})
end
