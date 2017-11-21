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
      sink_queues: %{},
      sink_ends: [],
    }
    {:ok, state}
  end

  def handle_pad_added(pad, :sink, state) do
    {:ok, state |> Helper.Map.put_in([:sink_queues, pad], <<>>)}
  end

  def handle_pad_removed(pad, state) do
    {:ok, state |> Helper.Map.remove_in([:sink_queues, pad])}
  end

  def handle_demand(:source, size, :bytes, _, %{sink_queues: queues} = state) do
    demands = queues
      |> Enum.map(fn {sink, q} -> {:demand, {sink,
          q |> byte_size ~> (s -> max 0, size - s)
        }} end)

    {{:ok, demands}, state}
  end

  def handle_event({:dynamic, :sink, _id} = sink, %Event{type: :eos}, _, state) do
    {:ok, state |> Map.update!(:sink_ends, & [sink | &1])}
  end
  def handle_event(pad, event, params, state) do
    super(pad, event, params, state)
  end

  def handle_process1(
    sink, %Buffer{payload: payload}, %{caps: caps}, %{sink_queues: queues, sink_ends: ends} = state
  ) do
    queues = queues |> Map.update!(sink, & &1 <> payload)

    time_frame = Caps.format_to_sample_size!(caps.format) * caps.channels

    min_size = queues
      |> Map.values
      |> Enum.map(&byte_size/1)
      |> Enum.min
      |> int_part(time_frame)

    if min_size == 0 do
      {:ok, %{state | sink_queues: queues}}
    else
      {payloads, queues} = queues
        |> Enum.map(fn {s, <<p::binary-size(min_size), nq::binary>>} -> {p, {s, nq}} end)
        |> Enum.unzip

      payload = payloads |> DoMix.mix(caps)
      queues = queues |> Map.new

      {ends, queues} = ends |> Enum.flat_map_reduce(queues, fn sink, queues ->
          case queues[sink] do
            q when byte_size(q) < time_frame -> {[], queues |> Map.delete(sink)}
            _ -> {[sink], queues}
          end
        end)

      {
        {:ok, buffer: {:source, %Buffer{payload: payload}}},
        %{state | sink_queues: queues, sink_ends: ends}
      }
    end
  end

end
