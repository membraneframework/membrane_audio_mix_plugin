defmodule Membrane.Element.AudioMixer.AlignerOptions do
  defstruct \
    chunk_time: nil
end

defmodule Membrane.Element.AudioMixer.Aligner do

  import Enum
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Element.AudioMixer.AlignerOptions
  alias Array

  @source_types [
      %Raw{format: :s32le},
      %Raw{format: :s16le},
      %Raw{format: :u32le},
      %Raw{format: :u16le},
      %Raw{format: :s8},
      %Raw{format: :u8},
    ]

  @source_pads [sink0: 0, sink1: 1, sink2: 2]

  def_known_source_pads %{
    :sink0 => {:always, @source_types},
    :sink1 => {:always, @source_types},
    :sink2 => {:always, @source_types},
  }

  def_known_sink_pads %{
    :source => {:always, [
      %Raw{format: :s32le},
      %Raw{format: :s16le},
      %Raw{format: :u32le},
      %Raw{format: :u16le},
      %Raw{format: :s8},
      %Raw{format: :u8},
    ]}
  }

  @empty_queue @source_pads |> into(Array.new, fn _ -> <<>> end)
  @empty_to_drop @source_pads |> into(Array.new, fn _ -> 0 end)

  @doc false
  def handle_prepare(%AlignerOptions{chunk_time: chunk_time}) do
    {:ok, queue: @empty_queue, chunk_time: chunk_time, chunk_size: Nil, to_drop: @empty_to_drop}
  end

  @doc false
  def handle_caps({:sink, %Raw{sample_rate: sample_rate} = caps}, %{chunk_time: chunk_time} = state) do
    {:ok, %{state | caps: caps, queue: @empty_queue, to_drop: @empty_to_drop, chunk_size: trunc chunk_time*sample_rate/1000}}
  end

  @doc false
  def handle_buffer({sink, %Membrane.Buffer{payload: payload} = buffer}, %{queue: queue, to_drop: to_drop} = state) do
    sink_no = @source_pads[sink]
    sink_to_drop = to_drop[sink_no]
    cut_payload = case payload do
      <<_::binary-size(sink_to_drop)-unit(8)>> <> r -> r
      _ -> <<>>
    end
    new_to_drop = to_drop |> Array.set(sink_no, Kernel.max(0, sink_to_drop - byte_size payload))
    new_queue = queue |> Array.update(sink_no, &(&1 <> cut_payload))

    {:ok, [], %{state | queue: new_queue, to_drop: new_to_drop}}
  end

  defp unzip(enum, tuple_size, already_unzipped \\ []) when tuple_size >= 2 do
    if tuple_size == 2 do
      {a, b} = enum |> unzip
      ([b, a] ++ already_unzipped) |> reverse |> List.to_tuple
    else
      {a, b} = enum |> map(&{&1 |> elem(0), &1 |> Tuple.delete_at(0)}) |> unzip
      unzip b, tuple_size - 1, [a | already_unzipped]
    end
  end

  @doc false
  def handle_other(:tick, %{queue: queue, chunk_size: chunk_size, to_drop: to_drop} = state) do
    ready_data_size = Kernel.min(queue |> max_by(&byte_size/1), chunk_size)

    {payload, new_queue, new_to_drop} = zip(queue, to_drop)
      |> map(fn {data, to_drop} ->
          case data do
            <<p::binary-size(ready_data_size)-unit(8)>> <> r -> {p, r, to_drop}
            _ -> {data, <<>>, ready_data_size - byte_size(data)}
          end
        end)
      |> unzip(3)
      |> case do {p, q, d} -> {p, q |> into(Array.new), d |> into(Array.new)} end

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: payload}}}], %{state | queue: new_queue, to_drop: new_to_drop}}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
