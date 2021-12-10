defmodule MyMatchers do
  import ExUnit.Assertions
  import ExMatchers.Custom

  defmodule QueueElementsAreEqual do
    # for lists of elements with the same size
    def to_match(elements, other_elements) do
      assert are_equal(elements, other_elements)
    end

    def to_not_match(elements, other_elements) do
      refute are_equal(elements, other_elements)
    end

    defp are_equal(elements, other_elements) do
      case elements do
        [] -> true
        [elem] -> is_equal(elem, List.first(other_elements))
        true -> 
          [head | tail] = elements
          [other_head | other_tail] = other_elements
          is_equal(head, other_head) and are_equal(tail, other_tail)
      end
    end

    defp is_equal(element, other_element) do
      (element.consumers_that_did_not_ack == other_element.consumers_that_did_not_ack and
      element.message.payload == other_element.message.payload and
      element.number_of_attempts == other_element.number_of_attempts)
    end
  end
  defmatcher be_equal(other_elements), matcher: QueueElementsAreEqual
end