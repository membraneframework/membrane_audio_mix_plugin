defmodule Membrane.AudioInterleaver.DoInterleave do
  @moduledoc """
  Module responsible for interleaving audio tracks (all in the same format, with 1
  channel) in a given order.
  """
  alias Membrane.Pad

  require Membrane.Pad

  @doc """
  Order queues according to `order`, take `bytes_per_channel` from each queue
  (all queues must be at least `bytes_per_channel` long),
  and interleave them.
  """
  @spec interleave(pos_integer(), pos_integer(), %{}, [integer()]) :: {any(), map()}
  def interleave(bytes_per_channel, _sample_size, pads, _order) when map_size(pads) == 1 do
    [{pad, data}] = Map.to_list(pads)

    <<payload::binary-size(bytes_per_channel), remaining_queue::binary>> = data.queue
    pads = %{pad => %{data | queue: remaining_queue}}

    {payload, pads}
  end

  def interleave(bytes_per_channel, sample_size, _pads, _order)
      when rem(bytes_per_channel, sample_size) != 0 do
    raise("`bytes_per_channel` must be a mutliple of `sample_size`!
      Received respectively #{bytes_per_channel} and #{sample_size}")
  end

  def interleave(bytes_per_channel, sample_size, pads, order) do
    pads_inorder = order_pads(pads, order)
    {payloads, pads_list} = get_payloads(bytes_per_channel, pads_inorder)

    payload =
      payloads
      |> Enum.map(&Bunch.Binary.chunk_every(&1, sample_size))
      |> Enum.zip_with(&Enum.join/1)
      |> Enum.join()

    {payload, Map.new(pads_list)}
  end

  defp order_pads(pads, order) do
    order
    |> Enum.map(fn name ->
      pad = Pad.ref(:input, name)
      {pad, pads[pad]}
    end)
  end

  defp get_payloads(payload_size, pads_inorder) do
    pads_inorder
    |> Enum.map(fn
      {pad, %{queue: <<payload::binary-size(payload_size), rest::binary>>} = data} ->
        {payload, {pad, %{data | queue: rest}}}
    end)
    |> Enum.unzip()
  end
end
