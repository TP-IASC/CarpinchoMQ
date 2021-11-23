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

  def handle_call({:subscribe, pid}, _from, state) do
    if Enum.member?(state.subscribers, pid) do
      { :reply, :already_subscribed, state }
    else
      replica_name()
      |> Queue.cast({ :subscribe, pid })

      { :reply, :subscribed, %{ elements: state.elements, subscribers: [pid | state.subscribers] } }
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    unless Enum.member?(state.subscribers, pid) do
      { :reply, :not_subscribed, state }
    else
      replica_name()
      |> Queue.cast({ :unsubscribe, pid })

      { :reply, :unsubscribed, %{ elements: state.elements, subscribers: List.delete(state.subscribers, pid) } }
    end
  end

  defp replica_name(),
    do: String.to_atom(Atom.to_string(name()) <> "_replica")
end
