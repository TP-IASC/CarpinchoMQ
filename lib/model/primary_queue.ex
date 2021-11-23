defmodule PrimaryQueue do
  use Queue
  require Logger

  def init(name) do
    replica = replica_name()
    initial_state = %{ elements: [], subscribers: [] }
    state = if Queue.alive?(replica), do: Queue.state(replica), else: initial_state
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)

    { :ok, state }
  end

  def handle_cast({:push, payload}, state) do
    new_message = create_message(payload)

    replica_name()
    |> Queue.cast({ :push, new_message })

    { :noreply, %{ elements: [new_message | state.elements], subscribers: state.subscribers } }
  end

  def handle_cast({:subscribe, pid}, state) do
    replica_name()
    |> Queue.cast({ :subscribe, pid })

    { :noreply, %{ elements: state.elements, subscribers: [pid | state.subscribers] } }
  end

  defp replica_name(),
    do: String.to_atom(Atom.to_string(name()) <> "_replica")
end
