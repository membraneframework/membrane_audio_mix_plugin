defmodule Membrane.Element.AudioMixer.Mixer do
  use Membrane.Element.Base.Filter
  use Membrane.Helper
  alias Membrane.Element.AudioMixer.DoMix
  alias Membrane.{Buffer, Event}
  alias Membrane.Caps.Audio.Raw, as: Caps
  use Membrane.Mixins.Log, tags: :membrane_element_audiomixer

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }
  def_known_sink_pads %{
    {:dynamic, :sink} => {:always, {:pull, demand_in: :bytes}, :any}
  }

  def handle_init(_) do
    state = %{
      sinks: %{},
    }
    {:ok, state}
  end

  def handle_pad_added(_pad, %{direction: :sink}, state) do
    {:ok, state}
  end

  def handle_pad_removed({:dynamic, :sink, _} = pad, %{direction: :sink}, state) do
    {:ok, state |> Helper.Map.remove_in([:sinks, pad])}
  end

  def handle_demand(:source, size, :bytes, _, %{sinks: sinks} = state) do
    demands = sinks
      |> Enum.map(fn {sink, %{queue: q}} -> {:demand, {sink,
          q |> byte_size ~> (s -> max 0, size - s)
        }} end)

    {{:ok, demands}, state}
  end

  def handle_event({:dynamic, :sink, _id} = sink, %Event{type: :sos}, _, state) do
    info "mixer sos #{inspect sink}"
    new_channel = %Event{type: :channel_added, stick_to: :buffer}
    state = state |> Helper.Map.put_in([:sinks, sink], %{queue: <<>>, eos: false})
    {{:ok, event: {:source, new_channel}}, state}
  end
  def handle_event({:dynamic, :sink, _id} = sink, %Event{type: :eos}, params, state) do
    %{caps: caps} = params
    info "mixer eos #{inspect sink}"
    state = state |> Helper.Map.update_in([:sinks, sink], & %{&1 | eos: true})
    with {{:ok, actions}, state} <- do_handle_process(caps, state) do
      {{:ok, [event: {:source, %Event{type: :channel_removed}}] ++ actions}, state}
    end
  end
  def handle_event(pad, event, params, state) do
    super(pad, event, params, state)
  end

  def handle_process1(sink, buffer, params, state) do

    %Buffer{payload: payload} = buffer
    %{sinks: sinks} = state
    %{caps: caps} = params
    time_frame = Caps.format_to_sample_size!(caps.format) * caps.channels

    {size, sinks} = sinks
      |> Helper.Map.get_and_update_in([sink, :queue],
        & {&1 |> byte_size, &1 <> payload})

    if size >= time_frame do
      do_handle_process caps, %{state | sinks: sinks}
    else
      {:ok, %{state | sinks: sinks}}
    end
  end

  defp do_handle_process(caps, state) do
    %{sinks: sinks} = state
    time_frame = Caps.format_to_sample_size!(caps.format) * caps.channels
    mix_size = mix_size(sinks, time_frame)
    if mix_size >= time_frame do
      {payload, sinks} = mix(sinks, mix_size, caps)

      sinks = sinks |> remove_finished_sinks(time_frame)

      {{:ok, buffer: {:source, %Buffer{payload: payload}}}, %{state | sinks: sinks}}
    else
      {{:ok, []}, %{state | sinks: sinks}}
    end
  end

  defp mix_size(sinks, time_frame) do
    fallback = fn ->
        sinks
          |> Enum.map(fn {_sink, %{queue: q}} -> byte_size q end)
          |> Enum.max
      end
    sinks
      |> Enum.flat_map(fn
          {_sink, %{queue: q, eos: false}} -> [byte_size q]
          _ -> []
        end)
      |> Enum.min(fallback)
      |> int_part(time_frame)
  end

  defp mix(sinks, mix_size, _caps) when map_size(sinks) == 1 do
    {sink, data} = sinks |> Map.to_list |> hd
    %{queue: <<p::binary-size(mix_size), q::binary>>} = data
    {p, %{sink => %{data | queue: q}}}
  end

  defp mix(sinks, mix_size, caps) do
    {payloads, sinks} = sinks
      |> Enum.map(fn
          {sink, %{queue: <<payload::binary-size(mix_size), nq::binary>>} = data} ->
            {payload, {sink, %{data | queue: nq}}}
          {sink, %{queue: payload} = data} ->
            {payload, {sink, %{data | queue: <<>>}}}
        end)
      |> Enum.unzip

    payload = payloads |> DoMix.mix(caps)
    sinks = sinks |> Map.new
    {payload, sinks}
  end

  defp remove_finished_sinks(sinks, time_frame) do
    sinks
      |> Enum.flat_map(fn
          {_sink, %{queue: q, eos: true}} when byte_size(q) < time_frame -> []
          sink_data -> [sink_data]
        end)
      |> Map.new
  end

end
