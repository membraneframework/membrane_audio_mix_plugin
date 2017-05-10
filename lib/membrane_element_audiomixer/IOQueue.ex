defmodule Membrane.Element.AudioMixer.IOQueue do

  def new, do: Qex.new

  def new init do
    Qex.new |> push(init)
  end

  def push(q, binary) when is_binary binary do
    push q, [binary]
  end
  def push(q, iolist) when is_list iolist do
    Qex.push q, iolist
  end

  def pop q do
    Qex.pop q
  end
  def pop q, :binary do
    case Qex.pop q do
      {{:value, value}, new_q} ->
        case value do
          [] -> pop new_q, :binary
          [h|t] -> {{:value, h}, new_q |> Qex.push(t)}
        end
      empty -> empty
    end
  end
  defp pop_bytes_r q, bytes, acc \\ [] do
    case pop q, :binary do
      {{:value, b}, new_q} ->
        case b do
          <<_::binary-size(bytes)>> ->
            {{:value, [b | acc]}, new_q}
          <<b_cut::binary-size(bytes)>> <> rem ->
            {{:value, [b_cut | acc]}, new_q |> Qex.push_front([rem])}
          _ -> pop_bytes_r new_q, bytes - byte_size(b), [b | acc]
        end
      {:empty, new_q} -> {{:empty, acc}, new_q}
    end
  end
  def pop q, bytes do
    {{t, r}, q} = pop_bytes_r q, bytes
    {{t, r |> Enum.reverse}, q}
  end

end
