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
  def handle_buffer({sink, %Membrane.Buffer{payload: payload} = buffer}, %{queue: queue} = state) do
    new_queue = queue |> Array.update(@source_pads[sink], &(&1 <> payload))
    {:ok, [], %{state | queue: new_queue}}
  end

  @doc false
  def handle_other(:tick, %{queue: queue, chunk_size: chunk_size, to_drop: to_drop} = state) do
    ready_data_size = Kernel.min(queue |> max_by(&byte_size/1), chunk_size)
    payload = queue |> map(&case &1 do
      <<p::binary-size(ready_data_size)-unit(8)>> <> _ -> p
      p -> p
    end)

    new_queue = queue |> into(Array.new, &case &1 do
        <<_::binary-size(ready_data_size)-unit(8)>> <> r -> r
        _ -> <<>>
      end)

    new_to_drop = to_drop |> with_index |> into(Array.new, fn {v, k} -> v + Kernel.max(0, ready_data_size - byte_size queue[k]) end)

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: payload}}}], %{state | queue: new_queue, to_drop: new_to_drop}}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
