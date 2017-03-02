defmodule Membrane.Element.AudioMixer.Aligner do

  import Enum
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw

  @source_types [
      %Raw{format: :s32le},
      %Raw{format: :s16le},
      %Raw{format: :u32le},
      %Raw{format: :u16le},
      %Raw{format: :s8},
      %Raw{format: :u8},
    ]

  @source_pads [:sink0, :sink1, :sink2]

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

  @empty_queue @source_pads |> into(%{}, &{&1, <<>>})

  @doc false
  def handle_prepare(_) do
    {:ok, queue: @empty_queue}
  end

  @doc false
  def handle_caps({:sink, caps}, state) do
    {:ok, %{state | caps: caps, queue: @empty_queue}}
  end

  @doc false
  def handle_buffer({sink, %Membrane.Buffer{payload: payload} = buffer}, %{queue: queue} = state) do
    new_queue = queue |> Map.update!(sink, &(&1 <> payload))
    {:ok, [], %{state | queue: new_queue}}
  end

  @doc false
  def handle_other(:tick, %{queue: queue} = state) do
    payload = queue |> into([], fn {_, v} -> v end)
    {:ok, [{:send, {:source, %Membrane.Buffer{payload: payload}}}], state}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
