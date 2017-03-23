defmodule Membrane.Element.AudioMixer.AlignerOptions do
  defstruct \
    chunk_time: nil
end

defmodule Membrane.Element.AudioMixer.Aligner do
  @moduledoc """
  This module (used by Mixer) collects data from multiple (currently three)
  paths, and every chunk_time forwards it through the sink. If some samples do
  not arrive on time, buffer is sent without them, and they are omitted when they
  finally arrive. If all paths lack samples, remaining_samples_cnt is the number
  of lacking samples in the longest path, otherwise it is set to 0. Sent data
  is a map consisting of list of paths (binaries) and remaining_samples_cnt.
  Sent paths may contain incomplete samples, which need to be cut off.
  """

  import Enum
  import Membrane.Helper.Enum
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Element.AudioMixer.AlignerOptions
  alias Array
  alias Membrane.Time

  @sink_types [
      %Caps{format: :f32le},
      %Caps{format: :s32le},
      %Caps{format: :s16le},
      %Caps{format: :u32le},
      %Caps{format: :u16le},
      %Caps{format: :s8},
      %Caps{format: :u8},
    ]

  @sink_pads %{sink0: 0, sink1: 1, sink2: 2}

  def_known_sink_pads %{
    :sink0 => {:always, @sink_types},
    :sink1 => {:always, @sink_types},
    :sink2 => {:always, @sink_types},
  }

  def_known_source_pads %{
    :source => {:always, [
      %Caps{format: :f32le},
      %Caps{format: :s32le},
      %Caps{format: :s16le},
      %Caps{format: :u32le},
      %Caps{format: :u16le},
      %Caps{format: :s8},
      %Caps{format: :u8},
    ]}
  }

  @empty_queue @sink_pads |> into(Array.new, fn _ -> <<>> end)
  @empty_to_drop @sink_pads |> into(Array.new, fn _ -> 0 end)


  @doc false
  def handle_init(%AlignerOptions{chunk_time: chunk_time}) do
    {:ok, queue: @empty_queue, chunk_time: chunk_time, to_drop: @empty_to_drop, timer: Nil, previous_tick: Nil}
  end

  @doc false
  def handle_play(%{chunk_time: chunk_time} = state) do
    {:ok, timer} = :timer.send_interval(chunk_time/(1 |> Time.millisecond) |> trunc, :tick)
    %{state | timer: timer, previous_tick: Time.native_monotonic_time}
  end

  @doc false
  def handle_caps(_sink, %Caps{sample_rate: sample_rate, format: format} = caps, state) do
    sample_size = Caps.format_to_sample_size format
    {
      :ok,
      [{:caps, {:source, caps}}],
      %{state |
        sample_size: sample_size,
        sample_rate: sample_rate,
        queue: @empty_queue,
        to_drop: @empty_to_drop,
      }
    }
  end

  @doc false
  def handle_buffer(sink, _caps, %Membrane.Buffer{payload: payload}, %{queue: queue, to_drop: to_drop} = state) do
    %{^sink => sink_no} = @sink_pads
    sink_to_drop = to_drop[sink_no]
    cut_payload = case payload do
      <<_::binary-size(sink_to_drop)-unit(8)>> <> r -> r
      _ -> <<>>
    end
    new_to_drop = to_drop |> Array.set(sink_no, Kernel.max(0, sink_to_drop - byte_size payload))
    new_queue = queue |> Array.update(sink_no, &(&1 <> cut_payload))

    {:ok, [], %{state | queue: new_queue, to_drop: new_to_drop}}
  end

  defp current_chunk_size(current_tick, previous_tick, sample_size, sample_rate) do
    duration = current_tick - previous_tick
    trunc sample_size*duration*sample_rate/Time.native_resolution
  end

  @doc false
  def handle_other(:tick, %{queue: queue, to_drop: to_drop, sample_size: sample_size, sample_rate: sample_rate, previous_tick: previous_tick} = state) do
    current_tick = Time.native_monotonic_time
    chunk_size = current_chunk_size current_tick, previous_tick, sample_size, sample_rate
    {data, new_queue, new_to_drop} = zip(queue, to_drop)
      |> map(fn {data, to_drop} ->
          case data do
            <<p::binary-size(chunk_size)-unit(8)>> <> r -> {p, r, to_drop}
            _ -> {data, <<>>, chunk_size - byte_size(data)}
          end
        end)
      |> unzip!(3)
      |> case do {p, q, d} -> {p, q |> into(Array.new), d |> into(Array.new)} end

    remaining_samples_cnt = (chunk_size - byte_size(data |> max_by(&byte_size/1))) / sample_size |> Float.ceil |> trunc

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: %{data: data, remaining_samples_cnt: remaining_samples_cnt}}}}], %{state | queue: new_queue, to_drop: new_to_drop, previous_tick: current_tick}}
  end

  @doc false
  def handle_stop(%{timer: timer} = state) do
    {:ok, :cancel} = :timer.cancel timer
    {:ok, %{state | timer: Nil, previous_tick: Nil}}
  end
end
