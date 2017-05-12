defmodule Membrane.Element.AudioMixer.AlignerOptions do
  defstruct \
    chunk_time: nil,
    buffer_reserve_factor: 0.5
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
  use Membrane.Element.Base.Source
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Element.AudioMixer.AlignerOptions
  alias Membrane.Element.AudioMixer.IOQueue
  alias Membrane.Time
  use Membrane.Mixins.Log

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
  def handle_init %AlignerOptions{chunk_time: chunk_time, buffer_reserve_factor: buffer_reserve_factor} do
    if chunk_time < (1 |> Time.millisecond) do
      {:error, "aligner: chunk time must be greater or equal to 1 millisecond"}
    else
      {:ok, %{sink_data: %{}, sinks_to_remove: [], chunk_time: chunk_time, buffer_reserve_factor: buffer_reserve_factor, timer: nil, previous_tick: nil, caps: nil}}
    end
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



  defp add_sink sink_data, sink do
    sink_data |> Map.put(sink, %{queue: IOQueue.new, to_drop: 0, first_play: true})
  end

  defp init_timer chunk_time do
    {:ok, timer} = :timer.send_interval(chunk_time/(1 |> Time.millisecond) |> trunc, :tick)
    timer
  end

  @doc false
  def handle_other {:new_sink, sink, nil}, state do
    warn "audioaligner does not accept nil caps, received from sink #{inspect sink}"
    {:error, :aligner_nil_caps, state}
  end
  @doc false
  def handle_other({:new_sink, sink, caps}, %{sink_data: sink_data, caps: current_caps} = state) when caps == current_caps do
    debug "aligner: new sink: #{inspect sink}"
    {:ok, %{state | sink_data: sink_data |> add_sink(sink)}}
  end
  @doc false
  def handle_other({:new_sink, sink, caps}, %{sink_data: sink_data, caps: current_caps, chunk_time: chunk_time, timer: timer} = state)
  when sink_data == %{} do
    debug "aligner: new sink: #{inspect sink}, setting caps to #{inspect caps}"
    {:ok, [{:caps, {:source, caps}}], %{state |
      caps: caps,
      sink_data: sink_data |> add_sink(sink),
      timer: if timer == nil do init_timer chunk_time else timer end,
      previous_tick: Time.native_monotonic_time,
    }}
  end
  @doc false
  def handle_other {:new_sink, sink, caps}, state do
    warn "audioaligner received incompatible caps #{inspect caps} from sink #{inspect sink}"
    {:error, :aligner_incompatible_caps, state}
  end

  def handle_other {:remove_sink, sink}, %{sink_data: sink_data, sinks_to_remove: sinks_to_remove} = state do
    debug "aligner: removing sink: #{inspect sink}"
    new_state = case sink_data[sink].queue do
      <<>> -> %{state | sink_data: sink_data |> Map.delete(sink)}
      _ -> %{state | sinks_to_remove: [sink | sinks_to_remove]}
    end
    {:ok, new_state}
  end

  defp update_sink_data payload, %{queue: queue, to_drop: to_drop} = sink_data do
    if to_drop > 0 do
      warn "aligner: dropping #{Kernel.min to_drop, byte_size payload} of #{byte_size payload} received bytes, remaining to drop: #{Kernel.max 0, to_drop-byte_size payload} bytes"
    end
    cut_payload = case payload do
      <<_::binary-size(to_drop)-unit(8)>> <> r -> r
      _ -> <<>>
    end
    %{ sink_data |
      queue: queue |> IOQueue.push(cut_payload),
      to_drop: Kernel.max(0, to_drop - byte_size payload)
    }
  end

  @doc false
  def handle_other {sink, %Membrane.Buffer{payload: payload}}, %{sink_data: sink_data} = state do
    debug "aligner: received buffer from sink: #{inspect sink}, payload: #{inspect payload}"
    if sink_data |> Map.has_key?(sink) do
      {:ok, %{state |
        sink_data: sink_data |> Map.update!(sink, &(update_sink_data payload, &1))
      }}
    else
      warn "audioaligner has not recogized sink #{inspect sink}"
      {:error, :aligner_sink_not_recognized, state}
    end
  end

  defp current_chunk_size current_tick, previous_tick, %Caps{sample_rate: sample_rate, format: format, channels: channels} do
    {:ok, sample_size} = Caps.format_to_sample_size format
    chunk_samples = round sample_rate*(current_tick - previous_tick)/Time.native_resolution
    chunk_samples * channels * sample_size
  end

  defp extract_sink_data {sink, %{queue: queue, first_play: true} = sink_data}, chunk_size, buffer_reserve_factor, sample_size do
    if IOQueue.byte_length(queue) >= chunk_size * (1 + buffer_reserve_factor) do
      extract_sink_data {sink, %{sink_data | first_play: false}}, chunk_size, buffer_reserve_factor, sample_size
    else
      {nil, {sink, sink_data}}
    end
  end
  defp extract_sink_data {sink, %{queue: queue, to_drop: to_drop} = sink_data}, chunk_size, _buffer_reserve_factor, sample_size do
    case queue |> IOQueue.pop(chunk_size) do
      {{:value, p}, r} -> {p, {sink, %{sink_data | queue: r}}}#, to_drop: to_drop}}}
      {{:empty, p}, r} -> {p, {sink, %{sink_data | queue: r, to_drop: to_drop + chunk_size - IO.iodata_length(p)}}}
      # <<p::binary-size(chunk_size)-unit(8)>> <> r -> {p, {sink, %{sink_data | queue: r, to_drop: to_drop}}}
      # _ -> {queue, {sink, %{sink_data | queue: <<>>, to_drop: to_drop + chunk_size - byte_size(queue)}}}
    end
  end

  @doc false
  def handle_other :tick, %{sink_data: sink_data, sinks_to_remove: sinks_to_remove, caps: %Caps{format: format, sample_rate: sample_rate} = caps, previous_tick: previous_tick, buffer_reserve_factor: buffer_reserve_factor} = state do
    {:ok, sample_size} = Caps.format_to_sample_size format
    current_tick = Time.native_monotonic_time
    chunk_size = current_chunk_size current_tick, previous_tick, caps
    {payload, sink_data} = sink_data
      |> map(&extract_sink_data &1, chunk_size, buffer_reserve_factor, sample_size)
      |> unzip
      |> case do {d, s} -> {d |> filter(& &1 != nil), s |> into(%{}) } end

    {sinks_to_remove_now, sinks_to_remove} = sinks_to_remove |> split_with(&IOQueue.empty sink_data[&1].queue)
    sink_data = sink_data |> Map.drop(sinks_to_remove_now)

    max_payload_length = payload |> Stream.map(&IO.iodata_length/1) |> Enum.max(fn -> 0 end)
    remaining_samples_cnt = (chunk_size - max_payload_length) / sample_size |> Float.ceil |> trunc
    # remaining_samples_cnt = (chunk_size - byte_size(payload |> max_by(&byte_size/1, fn -> <<>> end))) / sample_size |> Float.ceil |> trunc

    debug "aligner: forwarding buffer #{inspect payload}"
    debug "aligner: delays (in samples): #{inspect sink_data |> into(%{},fn {k, v} -> {k, v.to_drop/sample_size} end)}"

    {:ok,
      [{:send, {:source, %Membrane.Buffer{payload: payload}}}]
      ++ if remaining_samples_cnt > 0 do [{:send, {:source, Membrane.Event.discontinuity remaining_samples_cnt}}] else [] end,
      %{state | sink_data: sink_data, sinks_to_remove: sinks_to_remove, previous_tick: current_tick}
    }
  end

  @doc false
  def handle_stop %{timer: timer} = state do
    if timer != nil do
      {:ok, :cancel} = :timer.cancel timer
    end
    {:ok, %{state | timer: nil, previous_tick: nil}}
  end
end
