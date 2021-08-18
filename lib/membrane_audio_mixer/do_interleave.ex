defmodule Membrane.AudioMixer.DoInterleave do
  @moduledoc """
  Module responsible for interleaving audio tracks (all in the same format, with 1
  channel) in a given order.
  """

  @doc """
  Order queues according to `order`, take `bytes_per_channel` from each queue
  (all queues must be at least `bytes_per_channel` long),
  and interleave them.
  """
  @spec interleave(pos_integer(), pos_integer(), %{}, [integer()]) :: {any(), map()}
  def interleave(bytes_per_channel, _sample_size, pads, _order) when map_size(pads) == 1 do
    [{pad, data}] = Map.to_list(pads)

    <<payload::binary-size(bytes_per_channel)>> <> remaining_queue = data.queue
    pads = %{pad => %{data | queue: remaining_queue}}

    {payload, pads}
  end

  def interleave(bytes_per_channel, sample_size, pads, order) do
    pads_inorder = order_pads(pads, order)
    {payloads, pads_list} = get_payloads(bytes_per_channel, pads_inorder)

    payload = interleave_binaries(payloads, sample_size)

    {payload, Map.new(pads_list)}
  end

  #  Interleave binaries, taking `sample_size` bytes at a time.
  defp interleave_binaries(payloads, sample_size)

  defp interleave_binaries(payloads, sample_size) do
    payloads
    # split each channel's payload into `sample_size` chunks (channels order is reversed)
    |> Enum.map(fn payload -> to_chunks_reversed(payload, sample_size) end)
    # zip corresponding chunks of different channels and concatenate them (channels order is again reversed)
    |> Enum.zip_reduce([], fn zipped_chunks, acc ->
      [join_binaries(zipped_chunks) | acc]
    end)
    |> join_binaries()
  end

  #  Split bitstring into chunks of `chunk_size`. Chunks are returned in reversed order.
  defp to_chunks_reversed(binary, chunk_size, acc \\ [])

  defp to_chunks_reversed(binary, chunk_size, acc) when byte_size(binary) <= chunk_size do
    [binary | acc]
  end

  defp to_chunks_reversed(binary, chunk_size, acc) do
    <<chunk::binary-size(chunk_size), rest::bitstring>> = binary
    to_chunks_reversed(rest, chunk_size, [<<chunk::binary-size(chunk_size)>> | acc])
  end

  defp order_pads(pads, order) do
    order
    |> Enum.map(fn name -> {Membrane.Pad, :input, name} end)
    |> Enum.map(fn pad -> {pad, pads[pad]} end)
  end

  defp get_payloads(payload_size, pads_inorder) do
    pads_inorder
    |> Enum.map(fn
      {pad, %{queue: <<payload::binary-size(payload_size)>> <> rest} = data} ->
        {payload, {pad, %{data | queue: rest}}}
    end)
    |> Enum.unzip()
  end

  # joins list of binaries into one binary
  defp join_binaries(binaries) do
    Enum.reduce(binaries, <<>>, &(&2 <> &1))
  end
end
