defmodule Membrane.Element.AudioMixer.Mixer do
  @moduledoc """
  This element mixes audio paths (all in the same format, with the same amount
  of channels and sample rate) received from audioaligner
  (Membrane.Element.AudioMixer.Aligner), and sends resulting single path forwards
  through the source, in the format mixed paths are encoded in. If overflow
  happens during mixing, it is being clipped to the max value of sample in this
  format.

  Buffer received from aligner is a map of the form %{data, remaining_samples_cnt}.
  Data is a list consisting of audio paths (binaries). If binaries contain
  incomplete samples, they are cut off. Remaining_samples_cnt is the smallest
  amount of samples that were not supplied on time to the aligner (considering
  single path). Mixer appends remaining_samples_cnt silent samples to the
  resulting path before forwarding it to the source.
  """

  alias Membrane.Time
  alias Membrane.Caps.Audio.Raw, as: Caps
  use Membrane.Mixins.Log
  use Membrane.Helper

  @doc false
  defp clipper_factory(format) do
    max_sample_value = Caps.sample_max(format)
    if Caps.is_signed(format) do
      min_sample_value = Caps.sample_min(format)
      fn sample ->
        cond do
          sample > max_sample_value -> max_sample_value
          sample < min_sample_value -> min_sample_value
          true -> sample
        end
      end
    else
      fn sample ->
        if sample > max_sample_value do max_sample_value else sample end
      end
    end
  end

  defp do_mix(samples, mix_params, acc \\ 0)
  defp do_mix([], %{format: format, clipper: clipper}, acc) do
    acc |> clipper.() |> Caps.value_to_sample(format) ~> ({:ok, sample} -> sample)
  end
  defp do_mix([h|t], %{format: format} = mix_params, acc) do
    do_mix t, mix_params, h |> Caps.sample_to_value(format) ~> ({:ok, v} -> acc + v)
  end

  defp mix_params(format) do
    %{format: format, clipper: clipper_factory(format)}
  end


  defp zip_longest_binary_by binaries, chunk_size, zipper, acc \\ [] do
    {chunks, rests} = binaries
      |> Enum.flat_map(fn
        <<chunk::binary-size(chunk_size)>> <> rest -> [{chunk, rest}]
        _ -> []
      end)
      |> Enum.unzip
    case chunks do
      [] -> acc |> Enum.reverse |> IO.iodata_to_binary
      _ -> zip_longest_binary_by rests, chunk_size, zipper, [zipper.(chunks) | acc]
    end
  end

  @doc false
  def mix(buffers, %Caps{format: format}) do
    {:ok, sample_size} = Caps.format_to_sample_size(format)
    t = Time.native_monotonic_time

    buffer = buffers
      |> zip_longest_binary_by(sample_size, fn buf -> do_mix buf, format |> mix_params end)

    debug "mixing time: #{(Time.native_monotonic_time - t) * 1000 / Time.native_resolution} ms, buffer size: #{byte_size buffer}"

    buffer
  end

end
