defmodule Membrane.Element.AudioMixer.MixerOptions do
end

defmodule Membrane.Element.AudioMixer.Mixer do

  import Enum
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Element.AudioMixer.MixerOptions

  def_known_source_pads %{
    :sink0 => {:always, []},
    :sink1 => {:always, []},
    :sink2 => {:always, []}
  }

  @source_pads [:sink0, :sink1, :sink2]

  def source_pads, do: @source_pads

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

  defp empty_queue do
    @source_pads |> flat_map( &%{&1 => << >>} )
  end

  @doc false
  def handle_prepare(_) do
    {:ok, %{queue: empty_queue()}}
  end

  @doc false
  def handle_caps({_sink, caps}, state) do
    {:ok, %{state | queue: empty_queue(), caps: caps}}
  end

  @doc false
  def handle_buffer({sink, %Membrane.Buffer{payload: payload} = buffer}, %{caps: caps, queue: queue} = state) do
    
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
