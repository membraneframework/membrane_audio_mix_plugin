defmodule Membrane.AudioMixer.DoInterleave do
  alias Membrane.Caps.Audio.Raw, as: Caps

  @spec interleave(pos_integer(), Caps.t(), %{}, [integer()]) :: {any, map}
  def interleave(size, _caps, pads, _order) when map_size(pads) == 1 do
    [{pad, data}] = Map.to_list(pads)

    <<payload::binary-size(size)>> <> remaining_queue = data.queue
    pads = %{pad => %{data | queue: remaining_queue}}
    {payload, pads}
  end

  def interleave(bytes_per_channel, caps, pads, order) do
    sample_size = Caps.sample_size(caps)
    pads_inorder = order_pads(pads, order)

    {payloads, pads_list} = get_payloads(bytes_per_channel, pads_inorder)

    payload = do_interleave(payloads, sample_size)
    pads = Map.new(pads_list)

    {payload, pads}
  end

  defp order_pads(pads, order) do
    order
    |> Enum.map(fn nr -> {Membrane.Pad, :input, nr} end)
    |> Enum.map(fn pad -> {pad, pads[pad]} end)
    |> Enum.to_list()
  end

  # get channels' payloads of given size from their queues
  # (all queues must be at least 'payload_size' long)
  defp get_payloads(payload_size, pads_inorder) do
    pads_inorder
    |> Enum.map(fn
      {pad, %{queue: <<payload::binary-size(payload_size)>> <> rest} = data} ->
        {payload, {pad, %{data | queue: rest}}}
    end)
    |> Enum.unzip()
  end

  # interleave channels' payloads
  @spec do_interleave([binary()], pos_integer()) :: any
  def do_interleave(payloads, sample_size)

  def do_interleave(payloads, sample_size) do
    payloads
    # split each channel's payload into 'sample_size' chunks (channels order is reversed)
    |> Enum.map(fn payload -> to_chunks_reversed(payload, sample_size) end)
    # zip corresponding chunks of different channels and concatenate them (channels order is again reversed)
    |> Enum.zip_reduce([], fn zipped_chunks, acc ->
      [join_binaries(zipped_chunks) | acc]
    end)
    # reverse to concatenate smaller binary
    |> Enum.reverse()
    |> Enum.reduce(<<>>, &(&1 <> &2))
  end

  # joins list of binaries into one binary
  defp join_binaries(binaries) do
    Enum.reduce(binaries, <<>>, &(&2 <> &1))
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
end
