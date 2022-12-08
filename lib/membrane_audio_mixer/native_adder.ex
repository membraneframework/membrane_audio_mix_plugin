defmodule Membrane.AudioMixer.NativeAdder do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). The result is a single track in the format mixed tracks are encoded in.
  If overflow happens during mixing, a wave will be scaled down to the max sample value. Uses NIFs
  for mixing.

  Description of the algorithm:
  - Start with an empty queue
  - Enqueue merged values while the sign of the values remains the same
  - If the sign of values changes or adder is flushed:
    - If none of the values overflows limits of the format, convert the queued values
      to binary samples and return them
    - Otherwise, scale down the queued values, so the peak of the wave will become
      maximal (minimal) allowed value, then convert it to binary samples and return
      them.
  """

  @behaviour Membrane.AudioMixer.Mixer

  alias Membrane.AudioMixer.Mixer.Native
  alias Membrane.RawAudio

  @enforce_keys [:mixer_ref]
  defstruct @enforce_keys

  @impl true
  def init(%RawAudio{channels: channels, sample_format: format, sample_rate: sample_rate}) do
    {:ok, mixer_ref} = Native.init(channels, RawAudio.SampleFormat.serialize(format), sample_rate)

    %__MODULE__{mixer_ref: mixer_ref}
  end

  @impl true
  def mix(buffers, %__MODULE__{mixer_ref: mixer_ref}) do
    {:ok, buffer, mixer_ref} = Native.mix(buffers, mixer_ref)
    {buffer, %__MODULE__{mixer_ref: mixer_ref}}
  end

  @impl true
  def flush(%__MODULE__{mixer_ref: mixer_ref}) do
    {:ok, buffer, mixer_ref} = Native.flush(mixer_ref)
    {buffer, %__MODULE__{mixer_ref: mixer_ref}}
  end
end
