defmodule Membrane.AudioMixer.DoMix do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). Result is a single path in the format mixed paths are encoded in.
  If overflow happens during mixing, it is being clipped to the max value of sample in this format.
  """

  alias Membrane.AudioMixer.Helpers
  alias Membrane.Caps.Audio.Raw

  @doc """
  Mixes `buffers` to one buffer. Given buffers should have equal sizes. It uses information about
  samples provided in `caps`.
  """
  @spec mix([binary()], Membrane.Caps.Audio.Raw.t()) :: binary()
  def mix(buffers, caps) do
    sample_size = Raw.sample_size(caps)

    buffer =
      buffers
      |> Helpers.zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, mix_params(caps)) end)
      |> IO.iodata_to_binary()

    buffer
  end

  defp mix_params(caps) do
    %{caps: caps, clipper: clipper_factory(caps)}
  end

  defp clipper_factory(caps) do
    max_sample_value = Raw.sample_max(caps)
    min_sample_value = Raw.sample_min(caps)

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
    |> Raw.value_to_sample(caps)
  end

  defp do_mix([sample | samples], %{caps: caps} = mix_params, acc) do
    acc =
      sample
      |> Raw.sample_to_value(caps)
      |> then(&(&1 + acc))

    do_mix(samples, mix_params, acc)
  end
end
