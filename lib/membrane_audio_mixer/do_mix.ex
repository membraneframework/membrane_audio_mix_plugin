defmodule Membrane.AudioMixer.DoMix do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). Result is a single path in the format mixed paths are encoded in.
  If overflow happens during mixing, it is being clipped to the max value of sample in this format.
  """

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
      |> zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, mix_params(caps)) end)

    buffer
  end

  defp mix_params(caps) do
    %{caps: caps, clipper: clipper_factory(caps)}
  end

  defp clipper_factory(caps) do
    max_sample_value = Raw.sample_max(caps)

    if Raw.signed?(caps) do
      min_sample_value = Raw.sample_min(caps)

      fn sample ->
        cond do
          sample > max_sample_value -> max_sample_value
          sample < min_sample_value -> min_sample_value
          true -> sample
        end
      end
    else
      fn sample ->
        if sample > max_sample_value do
          max_sample_value
        else
          sample
        end
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

  defp zip_longest_binary_by(binaries, chunk_size, zipper, acc \\ []) do
    {chunks, rests} =
      binaries
      |> Enum.flat_map(fn
        <<chunk::binary-size(chunk_size), rest::binary>> -> [{chunk, rest}]
        _binary -> []
      end)
      |> Enum.unzip()

    case chunks do
      [] ->
        acc
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      _chunks ->
        zip_longest_binary_by(rests, chunk_size, zipper, [zipper.(chunks) | acc])
    end
  end
end
