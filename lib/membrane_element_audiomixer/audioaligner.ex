defmodule Membrane.Element.AudioMixer.AlignerOptions do
  defstruct \
    chunk_time: nil
end

defmodule Membrane.Element.AudioMixer.Aligner do
  @moduledoc """
  This module (used by Mixer) collects data from multiple (currently three)
  paths, and every chunk_time forwards it through the source. If some samples do
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
  alias Membrane.Time

  # @sink_types [
  #     %Caps{format: :f32le},
  #     %Caps{format: :s32le},
  #     %Caps{format: :s16le},
  #     %Caps{format: :u32le},
  #     %Caps{format: :u16le},
  #     %Caps{format: :s8},
  #     %Caps{format: :u8},
  #   ]
  #
  # def_known_sink_pads %{
  #   :sink0 => {:always, @sink_types},
  #   :sink1 => {:always, @sink_types},
  #   :sink2 => {:always, @sink_types},
  # }

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


  @doc false
  def handle_init %AlignerOptions{chunk_time: chunk_time} do
    #TODO: here only init sample size and sample rate to Nil, set them up in handle_caps / handle_new_sink
    {:ok, %{sink_data: %{}, chunk_time: chunk_time, timer: Nil, previous_tick: Nil, caps: Nil}}
  end

  @doc false
  def handle_play %{chunk_time: chunk_time} = state do
    {:ok, timer} = :timer.send_interval(chunk_time/(1 |> Time.millisecond) |> trunc, :tick)
    %{state | timer: timer, previous_tick: Time.native_monotonic_time}
  end

  # @doc false
  # def handle_caps(_sink, %Caps{sample_rate: sample_rate, format: format} = caps, state) do
  #   sample_size = Caps.format_to_sample_size format
  #   {
  #     :ok,
  #     [{:caps, {:source, caps}}],
  #     %{state |
  #       sample_size: sample_size,
  #       sample_rate: sample_rate,
  #     }
  #   }
  # end

  @doc false
  def handle_other {:new_sink, sink, caps}, %{sink_data: sink_data} = state do
    # TODO: verify caps
    {:ok, [], %{state |
      caps: caps,
      sink_data: sink_data |> Map.put(sink, %{queue: <<>>, to_drop: 0, first_play: true})
    }}
  end
  #TODO: add sink removal handler

  defp update_sink_data payload, %{queue: queue, to_drop: to_drop} = sink_data do
    cut_payload = case payload do
      <<_::binary-size(to_drop)-unit(8)>> <> r -> r
      _ -> <<>>
    end
    %{ sink_data |
      queue: queue <> cut_payload,
      to_drop: Kernel.max(0, to_drop - byte_size payload)
    }
  end

  @doc false
  def handle_other {sink, %Membrane.Buffer{payload: payload}}, %{sink_data: sink_data} = state do
    {:ok, [], %{state |
      sink_data: sink_data |> Map.update!(sink, &(update_sink_data payload, &1))
    }}
  end

  defp current_chunk_size current_tick, previous_tick, sample_size, sample_rate do
    duration = current_tick - previous_tick
    trunc sample_size*duration*sample_rate/Time.native_resolution
  end

  defp extract_sink_data {sink, %{first_play: true} = sink_data}, chunk_size do
     {Nil, {sink, %{sink_data | first_play: false}}}
  end
  defp extract_sink_data {sink, %{queue: queue, to_drop: to_drop} = sink_data}, chunk_size do
    case queue do
      <<p::binary-size(chunk_size)-unit(8)>> <> r -> {p, {sink, %{sink_data | queue: r, to_drop: to_drop}}}
      _ -> {queue, {sink, %{sink_data | queue: <<>>, to_drop: chunk_size - byte_size(queue)}}}
    end
  end


  @doc false
  def handle_other :tick, %{sink_data: sink_data, caps: %Caps{sample_rate: sample_rate, format: format} = caps, previous_tick: previous_tick} = state do
    {:ok, sample_size} = Caps.format_to_sample_size format
    current_tick = Time.native_monotonic_time
    chunk_size = current_chunk_size current_tick, previous_tick, sample_size, sample_rate
    {data, sink_data} = sink_data
      |> map(&extract_sink_data &1, chunk_size)
      |> unzip
      |> case do {d, s} -> {d |> filter(& &1 != Nil), s |> into(%{}) } end

    remaining_samples_cnt = (chunk_size - byte_size(data |> max_by(&byte_size/1, fn -> <<>> end))) / sample_size |> Float.ceil |> trunc

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: %{data: data, remaining_samples_cnt: remaining_samples_cnt}}}}], %{state | sink_data: sink_data, previous_tick: current_tick}}
  end

  @doc false
  def handle_stop %{timer: timer} = state do
    {:ok, :cancel} = :timer.cancel timer
    {:ok, %{state | timer: Nil, previous_tick: Nil}}
  end
end
