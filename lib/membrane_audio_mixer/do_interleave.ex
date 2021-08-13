defmodule Membrane.AudioMixer.DoInterleave do
  alias Membrane.Caps.Audio.Raw, as: Caps

  def interleave(size, _caps, pads, _order) when map_size(pads) == 1 do
    [{pad, data}] = Map.to_list(pads)

    <<payload::binary-size(size)>> <> remaining_queue = data.queue
    pads = %{pad => %{data | queue: remaining_queue}}
    {payload, pads}
  end

  def interleave(size, caps, pads, order) do
    pads_inorder =
      order
      |> Enum.map(fn nr -> {Membrane.Pad, :input, nr} end)
      |> Enum.map(fn pad -> {pad, pads[pad]} end)
      |> Enum.to_list()

    {payloads, pads_list} =
      pads_inorder
      |> Enum.map(fn
        {pad, %{queue: <<payload::binary-size(size)>> <> queue} = data} ->
          {payload, {pad, %{data | queue: queue}}}
      end)
      |> Enum.unzip()

    payload = do_interleave(payloads, caps)
    pads = Map.new(pads_list)

    {payload, pads}
  end

  def do_interleave(payloads, caps, acc \\ <<>>)

  def do_interleave([], caps, acc) do
    acc
  end

  # TODO implement
  def do_interleave(payloads, caps, acc) do
    sample_size = Caps.sample_size(caps)

    [heads, rests] =
      payloads
      |> Enum.map(fn b ->
        <<head::binary-size(sample_size)>> <> rest = b
        [head, rest]
      end)
      |> Enum.zip()

    heads = heads |> Tuple.to_list()
    IO.inspect(heads)

    do_interleave_short(payloads)
  end

  def split_in_chunks(mbinary, chunk_size, acc \\ [])

  def split_in_chunks(mbinary, chunk_size, acc) when byte_size(mbinary) <= chunk_size do
    Enum.reverse([mbinary | acc])
  end

  def split_in_chunks(mbinary, chunk_size, acc) do
    <<chunk::binary-size(chunk_size), rest::bitstring>> = mbinary
    split_in_chunks(rest, chunk_size, [<<chunk::binary-size(chunk_size)>> | acc])
  end

  def do_interleave_short(samples) do
    :erlang.list_to_binary(samples)
  end
end
