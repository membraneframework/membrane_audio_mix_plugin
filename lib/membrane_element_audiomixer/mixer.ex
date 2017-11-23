defmodule Membrane.Element.AudioMixer.Mixer do
  use Membrane.Element.Base.Filter
  use Membrane.Helper
  alias Membrane.Element.AudioMixer.DoMix
  alias Membrane.{Buffer, Event}
  alias Membrane.Caps.Audio.Raw, as: Caps
  use Membrane.Mixins.Log

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }
  def_known_sink_pads %{
    {:dynamic, :sink} => {:always, {:pull, demand_in: :bytes}, :any}
  }

  def handle_init(_) do
    state = %{
      sinks: %{},
      ending_sinks: [],
    }
    {:ok, state}
  end

  def handle_pad_added(pad, :sink, state) do
    {:ok, state |> Helper.Map.put_in([:sinks, pad], %{queue: <<>>})}
  end

  def handle_pad_removed(pad, state) do
    {:ok, state |> Helper.Map.remove_in([:sinks, pad])}
  end

  def handle_demand(:source, size, :bytes, _, %{sinks: sinks} = state) do
    demands = sinks
      |> Enum.map(fn {sink, %{queue: q}} -> {:demand, {sink,
          q |> byte_size ~> (s -> max 0, size - s)
        }} end)

    {{:ok, demands}, state}
  end

  def handle_event({:dynamic, :sink, _id} = sink, %Event{type: :eos}, _, state) do
    {:ok, state |> Map.update!(:ending_sinks, & [sink | &1])}
  end
  def handle_event(pad, event, params, state) do
    super(pad, event, params, state)
  end

  def handle_process1(
    sink, %Buffer{payload: payload}, %{caps: caps}, %{sinks: sinks, ending_sinks: ending} = state
  ) do
    sinks = sinks |> Helper.Map.update_in([sink, :queue], & &1 <> payload)

    time_frame = Caps.format_to_sample_size!(caps.format) * caps.channels

    min_size = min_size(sinks, time_frame)

    if min_size == 0 do
      {:ok, %{state | sinks: sinks}}
    else
      {payload, sinks} = mix(sinks, min_size, caps)

      {ending, sinks} = remove_finished_sinks(ending, sinks, time_frame)

      {
        {:ok, buffer: {:source, %Buffer{payload: payload}}},
        %{state | sinks: sinks, ending_sinks: ending}
      }
    end
  end


  defp min_size(sinks, time_frame) do
    sinks
      |> Enum.map(fn {_sink, %{queue: q}} -> q end)
      |> Enum.map(&byte_size/1)
      |> Enum.min
      |> int_part(time_frame)
  end

  defp mix(sinks, min_size, caps) do
    {payloads, sinks} = sinks
      |> Enum.map(fn {s, %{queue: <<p::binary-size(min_size), nq::binary>>}} -> {p, {s, %{queue: nq}}} end)
      |> Enum.unzip

    payload = payloads |> DoMix.mix(caps)
    sinks = sinks |> Map.new
    {payload, sinks}
  end

  defp remove_finished_sinks(ending_sinks, sinks, time_frame) do
    {ending, sinks} = ending_sinks |> Enum.flat_map_reduce(sinks, fn sink, sinks ->
        case sinks[sink].queue do
          q when byte_size(q) < time_frame -> {[], sinks |> Map.delete(sink)}
          _ -> {[sink], sinks}
        end
      end)
    {ending, sinks}
  end

end
