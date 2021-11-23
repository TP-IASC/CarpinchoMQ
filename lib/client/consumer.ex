defmodule Consumer do
  use GenServer
  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(state) do
    {:ok, state}
  end

  def subscribe(queue_name, pid) do
    Queue.cast(queue_name, { :subscribe, pid })
  end
end
