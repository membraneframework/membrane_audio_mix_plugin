defmodule Membrane.Element.AudioMixer.Aligner do
  use Membrane.Element.Base.Filter
  use Membrane.Helper
  alias Membrane.Element.AudioMixer.Mixer
  alias Membrane.Buffer

  @sinks [:sink1, :sink2]

  def_known_source_pads %{
    :source => {:always, :pull, :any}
  }
  def_known_sink_pads @sinks |> Enum.into(%{}, fn sink -> {sink, {:always, :pull, :any}} end)

  def handle_init(_) do
    state = %{sink_queues: @sinks |> Enum.into(%{}, fn sink -> {sink, Qex.new} end)}
    {:ok, state}
  end

  def handle_caps(:sink, caps, _, state) do
    {:ok, [{:caps, {:source, caps}}], state}
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

    if queues |> Enum.any?(&Enum.empty?/1) do
      {:ok, {[], state}}
    else
      queues
        |> Enum.map(fn q -> q |> Qex.pop ~> ({{:value, %Buffer{payload: p}}, nq} -> {p, nq}) end)
        |> Enum.unzip
        ~> ({payloads, queues} ->
            buffer = %Buffer{payload: payloads |> Mixer.mix(caps)}
            {:ok, {[{:buffer, {:source, buffer}}], %{state | sink_queues: queues}}}
          )
    end
  end

end
