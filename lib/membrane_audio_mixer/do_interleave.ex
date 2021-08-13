defmodule Membrane.AudioMixer.DoInterleave do
  alias Membrane.Caps.Audio.Raw, as: Caps

  def interleave(size, _caps, pads, _order) when map_size(pads) == 1 do
    [{pad, data}] = Map.to_list(pads)

    <<payload::binary-size(size)>> <> remaining_queue = data.queue
    pads = %{pad => %{data | queue: remaining_queue}}
    {payload, pads}
  end

  def interleave(size, caps, pads, order) do
    sample_size = Caps.sample_size(caps)

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

    payload = do_interleave(payloads, sample_size)
    pads = Map.new(pads_list)

    {payload, pads}
  end

  def do_interleave(payloads, sample_size)

  def do_interleave([], _sample_size) do
    <<>>
  end

  # TODO implement
  def do_interleave(payloads, sample_size) do
    payloads
    |> Enum.map(fn payload -> to_chunks_reversed(payload, sample_size) end)
    |> Enum.zip_reduce([], fn elems, acc ->
      elems = elems |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
      [elems | acc]
    end)
    |> Enum.reverse()
    |> Enum.reduce(<<>>, fn x, acc -> x <> acc end)
  end

  @spec to_chunks_reversed(bitstring, pos_integer(), list()) :: list
  def to_chunks_reversed(mbinary, chunk_size, acc \\ [])

  def to_chunks_reversed(mbinary, chunk_size, acc) when byte_size(mbinary) <= chunk_size do
    [mbinary | acc]
  end

  def to_chunks_reversed(mbinary, chunk_size, acc) do
    <<chunk::binary-size(chunk_size), rest::bitstring>> = mbinary
    to_chunks_reversed(rest, chunk_size, [<<chunk::binary-size(chunk_size)>> | acc])
  end

  def do_interleave_short(samples) do
    :erlang.list_to_binary(samples)
  end
end
