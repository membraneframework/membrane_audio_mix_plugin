defmodule Membrane.AudioMixer.NativeAdder do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). The result is a single path in the format mixed paths are encoded in.
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
