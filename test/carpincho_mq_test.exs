defmodule CarpinchoMqTest do
  use ExUnit.Case
  doctest CarpinchoMq

  test "greets the world" do
    assert CarpinchoMq.hello() == :world
  end
end
