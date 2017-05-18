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

  alias Membrane.Helper.Bitstring
  use Bitwise
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Event.Discontinuity.Payload, as: Discontinuity
  alias Membrane.Buffer
  alias Membrane.Time
  use Membrane.Mixins.Log

  def_known_source_pads %{
    :source => {:always, [
      %Caps{format: :f32le},
      %Caps{format: :s32le},
      %Caps{format: :s16le},
      %Caps{format: :u32le},
      %Caps{format: :u16le},
      %Caps{format: :s8},
      %Caps{format: :u8},
    ]}
  }

  def_known_sink_pads %{
    :sink => {:always, [
      %Caps{format: :f32le},
      %Caps{format: :s32le},
      %Caps{format: :s16le},
      %Caps{format: :u32le},
      %Caps{format: :u16le},
      %Caps{format: :s8},
      %Caps{format: :u8},
    ]}
  }

  def handle_init(_), do: {:ok, nil}

  @doc false
  def handle_caps(:sink, caps, state) do
    {:ok, [{:caps, {:source, caps}}], state}
  end

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

  defp mix(samples, mix_params, acc \\ 0)
  defp mix([], %{format: format, clipper: clipper}, acc) do
    {:ok, sample} = acc |> clipper.() |> Caps.value_to_sample(format)
    sample
  end
  defp mix([h|t], %{format: format} = mix_params, acc) do
    {:ok, value} = h |> Caps.sample_to_value(format)
    mix t, mix_params, acc + value
  end
  defp mix_params(format) do
    %{format: format, clipper: clipper_factory(format)}
  end

  def handle_event(:sink, %Caps{format: format}, %Membrane.Event{payload: %Discontinuity{duration: duration}}, state) do
    payload = fn -> Caps.sound_of_silence format end |> Stream.repeatedly |> Enum.take(duration) |> IO.iodata_to_binary
    {:ok, [{:send, {:source, %Buffer{payload: payload}}}], state}
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
  def handle_buffer(:sink, %Caps{format: format} = caps, %Buffer{payload: payload}, state) do
    {:ok, sample_size} = Caps.format_to_sample_size(format)
    t = Time.native_monotonic_time

    payload = payload
      |> Enum.map(&IO.iodata_to_binary/1)
      |> zip_longest_binary_by(sample_size, &mix(&1, mix_params format))

    debug "mixing time: #{(Time.native_monotonic_time - t) * 1000 / Time.native_resolution} ms, payload size: #{byte_size payload}"

    {:ok, [{:send, {:source, %Buffer{payload: payload}}}], state}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
