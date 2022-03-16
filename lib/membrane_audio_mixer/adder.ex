defmodule Membrane.AudioMixer.Adder do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). The result is a single path in the format mixed paths are encoded in.
  If overflow happens during mixing, it is being clipped to the max value of sample in this format.
  """

  @behaviour Membrane.AudioMixer.Mixer

  alias Membrane.AudioMixer.Helpers
  alias Membrane.RawAudio

  @enforce_keys [:caps, :clipper, :sample_size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          caps: RawAudio.t(),
          clipper: fun(),
          sample_size: integer()
        }

  @impl true
  def init(caps) do
    size = RawAudio.sample_size(caps)
    clipper = clipper_factory(caps)

    %__MODULE__{caps: caps, clipper: clipper, sample_size: size}
  end

  @impl true
  def mix(buffers, %__MODULE__{sample_size: sample_size} = state) do
    buffer =
      buffers
      |> Helpers.zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, state) end)
      |> IO.iodata_to_binary()

    {buffer, state}
  end

  @impl true
  def flush(state), do: {<<>>, state}

  defp clipper_factory(caps) do
    max_sample_value = RawAudio.sample_max(caps)
    min_sample_value = RawAudio.sample_min(caps)

    fn sample ->
      cond do
        sample > max_sample_value -> max_sample_value
        sample < min_sample_value -> min_sample_value
        true -> sample
      end
    end
  end

  defp do_mix(samples, mix_params, acc \\ 0)

  defp do_mix([], %{caps: caps, clipper: clipper}, acc) do
    acc
    |> clipper.()
    |> RawAudio.value_to_sample(caps)
  end

  defp do_mix([sample | samples], %{caps: caps} = mix_params, acc) do
    acc =
      sample
      |> RawAudio.sample_to_value(caps)
      |> then(&(&1 + acc))

    do_mix(samples, mix_params, acc)
  end
end
