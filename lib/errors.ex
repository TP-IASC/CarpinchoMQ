defmodule Errors do
  def name_not_allowed(queue_name),
    do: {:name_not_allowed, 403, "queue name #{inspect(queue_name)} is not allowed"}

  def queue_already_exists(queue_name),
    do: {:queue_already_exists, 409, "a queue named #{inspect(queue_name)} already exists"}

  def queue_not_found(queue_name),
    do: {:queue_not_found, 404, "a queue named #{inspect(queue_name)} does not exist"}

  def queue_max_size_exeded(max_size),
    do: {:max_size_exceded, 400, "queue max size (#{max_size}) cannot be exceded"}

  def invalid_work_mode(work_mode) do
    {:invalid_work_mode, 400, "Work mode \"#{work_mode}\" does not exist. Valid work modes are: :pub_sub and :work_queue"}
  end
end
