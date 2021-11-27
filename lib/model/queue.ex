defmodule Queue do
  defmacro __using__(_opts) do
    quote do
      use GenServer
      import Queue
      require Logger

      defstruct [:elements, :subscribers, :work_mode]

      def start_link(name) when is_atom(name) do
        GenServer.start_link(__MODULE__, name, name: via_tuple(name))
      end

      def handle_info({:EXIT, _from, {:name_conflict, {name, _value}, _registry_name, winning_pid}}, state) do
        Logger.info "Resolving conflicts in #{name}"
        GenServer.cast(winning_pid, {:horde, :resolve_conflict, state})
        { :stop, :normal, state }
      end

      # Por ahi conviene que sea call para que el proceso que envia la request tenga una confirmacion de recepcion
      def handle_cast({:horde, :resolve_conflict, remote_state}, state) do
        { :noreply, merge_queues(state.elements, remote_state.elements) } # quizas aca habria que mergear los estados completos
      end

      def handle_call(:get, _from, state) do
        { :reply, state, state }
      end

      def handle_cast({:set_work_mode, work_mode}, state) do
        { :noreply, %{ elements: state.elements, subscribers: state.subscribers, work_mode: work_mode } }
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

  def new(queue_name, work_mode) do
    {:ok, pid1} = Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {PrimaryQueue, queue_name})
    replica_name = String.to_atom(Atom.to_string(queue_name) <> "_replica")
    {:ok, pid2} = Horde.DynamicSupervisor.start_child(App.HordeSupervisor, {ReplicaQueue, replica_name})
    GenServer.cast(pid1, {:set_work_mode, work_mode})
    GenServer.cast(pid2, {:set_work_mode, work_mode})
    { pid1, pid2 }
  end
end
