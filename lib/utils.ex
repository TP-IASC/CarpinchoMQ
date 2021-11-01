defmodule Utils do
  def show_registry do
    specs = [{{:"$1", :"$2", :_ }, [], [%{ name: :"$1", pid: :"$2" }]}]
    Horde.Registry.select(App.HordeRegistry, specs)
  end
end
