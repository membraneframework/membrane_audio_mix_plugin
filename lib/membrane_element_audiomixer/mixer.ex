defmodule Membrane.Element.AudioMixer.Mixer do
  use Membrane.Element.Base.Filter
  use Membrane.Helper
  alias Membrane.Element.AudioMixer.DoMix
  alias Membrane.Buffer

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }
  def_known_sink_pads %{}

  def handle_init(_) do
    state = %{sink_queues: %{}}
    {:ok, state}
  end

  def handle_new_pad(_pad, :sink, _, state) do
    {:ok, {{:always, :pull, :any}, state}}
  end

  def handle_pad_added(pad, :sink, state) do
    {:ok, {[], state |> Helper.Map.put_in([:sink_queues, pad], Qex.new)}}
  end

  def handle_pad_removed(pad, state) do
    {:ok, {[], state |> Helper.Map.remove_in([:sink_queues, pad])}}
  end

  def handle_caps(_sink, caps, _, state) do
    {:ok, {[caps: {:source, caps}], state}}
  end

  def handle_demand(:source, size, _, %{sink_queues: queues} = state) do
    demands = queues
      |> Enum.map(fn {sink, q} -> {:demand, {sink,
          q |> Enum.count ~> (s -> max 0, size - s)
        }} end)

    {:ok, {demands, state}}
  end

  def handle_process1(sink, buffer, %{caps: caps}, %{sink_queues: queues} = state) do
    queues = queues
      |> Map.update!(sink, fn q -> q |> Qex.push(buffer) end)

    if queues |> Enum.any?(fn {_s, q} -> q |> Enum.empty? end) do
      {:ok, {[], %{state | sink_queues: queues}}}
    else
      queues
        |> Enum.map(fn {s, q} -> q |> Qex.pop ~> ({{:value, %Buffer{payload: p}}, nq} -> {p, {s, nq}}) end)
        |> Enum.unzip
        ~> ({payloads, queues} ->
            {%Buffer{payload: payloads |> DoMix.mix(caps)}, queues |> Enum.into(%{})})
        ~> ({buffer, queues} ->
            {:ok, {[buffer: {:source, buffer}], %{state | sink_queues: queues}}}
          )
    end
  end

end
