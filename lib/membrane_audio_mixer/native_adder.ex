defmodule Membrane.AudioMixer.NativeAdder do
  @moduledoc false

  @behaviour Membrane.AudioMixer.Mixer

  # alias Membrane.AudioMixer.Helpers
  alias Membrane.Caps.Audio.Raw
  alias Membrane.AudioMixer.Mixer.Native

  @impl true
  def init(caps) do
    params = %{
      sample_size: Raw.sample_size(caps),
      sample_max: Raw.sample_max(caps),
      sample_min: Raw.sample_min(caps)
    }

    {:ok, mixer_ref} = Native.init(params)

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
