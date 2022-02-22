defmodule Membrane.AudioMixer.NativeAdder do
  @moduledoc false

  @behaviour Membrane.AudioMixer.Mixer

  # alias Membrane.AudioMixer.Helpers
  alias Membrane.Caps.Audio.Raw
  alias Membrane.AudioMixer.Mixer.Native

  @impl true
  def init(%Raw{channels: channels, format: format, sample_rate: sample_rate}) do
    {:ok, mixer_ref} = Native.init(channels, Raw.Format.serialize(format), sample_rate)

    mixer_ref
  end

  @impl true
  def mix(buffers, mixer_ref) do
    Native.mix(buffers, mixer_ref)
    {<<>>, mixer_ref}
  end

  @impl true
  def flush(mixer_ref) do
    Native.flush(mixer_ref)
    {<<>>, mixer_ref}
  end
end
