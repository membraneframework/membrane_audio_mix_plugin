# defmodule Membrane.Element.AudioMixer.ListQueue do
#   def new(l \\ []) when is_list(l) do
#     l
#   end

#   def push l, e do
#     l ++ [e]
#   end

#   def push_front l, e do
#     [e | l]
#   end

#   def pop [] do
#     {:empty, []}
#   end
#   def pop [e | l] do
#     {{:value, e}, l}
#   end

#   def pop_back [] do
#     {:empty, []}
#   end
#   def pop_back l do
#     {e, l} = l |> List.pop_at(-1)
#     {{:value, e}, l}
#   end

# end
