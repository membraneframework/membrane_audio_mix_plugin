defmodule Membrane.Element.AudioMixer.Mixer do
  use Membrane.Element.Base.Filter
  use Membrane.Helper
  alias Membrane.Element.AudioMixer.DoMix
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw, as: Caps
  use Membrane.Mixins.Log

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }
  def_known_sink_pads %{
    {:dynamic, :sink} => {:always, {:pull, demand_in: :bytes}, :any}
  }

  def handle_init(_) do
    state = %{sink_queues: %{}}
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

  def handle_process1(sink, %Buffer{payload: payload}, %{caps: caps}, %{sink_queues: queues} = state) do
    queues = queues |> Map.update!(sink, & &1 <> payload)

    min_size = queues |> Map.values |> Enum.map(&byte_size/1) |> Enum.min

    if min_size < Caps.format_to_sample_size!(caps.format) * caps.channels do
      {:ok, %{state | sink_queues: queues}}
    else
      queues
        |> Enum.map(fn {s, <<p::binary-size(min_size), nq::binary>>} -> {p, {s, nq}} end)
        |> Enum.unzip
        ~> ({payloads, queues} ->
            {%Buffer{payload: payloads |> DoMix.mix(caps)}, queues |> Enum.into(%{})})
        ~> ({buffer, queues} ->
            {{:ok, buffer: {:source, buffer}}, %{state | sink_queues: queues}}
          )
    end
  end

end
