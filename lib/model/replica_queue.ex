defmodule ReplicaQueue do
  use Queue
  require Logger

  def init(name) do
    primary = primary_name()
    initial_state = %{ elements: [], subscribers: [] }
    state = if Queue.alive?(primary), do: Queue.state(primary), else: initial_state
    Logger.info "Queue: #{name} started"
    Process.flag(:trap_exit, true)
    { :ok, state }
  end


  def handle_cast({:push, message}, state) do
    { :noreply, %{ elements: [message | state.elements], subscribers: state.subscribers } }
  end


  defp sufix, do: "_replica"

  defp primary_name() do
    Atom.to_string(name())
    |> String.slice(0..-String.length(sufix())-1)
    |> String.to_atom
  end
end
