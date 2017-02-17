defmodule Membrane.Element.AudioMixer.MixerOptions do
  defstruct \
    pads_count: 5
end

defmodule Membrane.Element.AudioMixer.Mixer do

  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Element.AudioMixer.MixerOptions

  def_known_source_pads %{
    :sink => {:always, [
      %Raw{format: :s32le},
      %Raw{format: :s16le},
      %Raw{format: :u32le},
      %Raw{format: :u16le},
      %Raw{format: :s8},
      %Raw{format: :u8},
    ]}
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

  @doc false
  def handle_prepare(%MixerOptions{pads_count: pads_count}) do
  end

  @doc false
  def handle_buffer({:sink, %Membrane.Buffer{payload: payload} = buffer}, %{} = state) do
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
