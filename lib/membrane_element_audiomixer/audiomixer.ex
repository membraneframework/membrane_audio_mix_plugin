defmodule Membrane.Element.AudioMixer.Mixer do

  import Enum
  use Bitwise
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw

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
  def handle_caps({:sink, caps}, state) do
    {:ok, %{state | caps: caps}}
  end

  @doc false
  defp clipper_factory(format) do
    {:ok, sample_size} = Raw.format_to_sample_size(format)
    if CapsHelper.is_signed(format) do
      max_sample_value = (1 <<< (8*sample_size-1)) - 1
      min_sample_value = -(1 <<< (8*sample_size-1))
      fn sample ->
        cond do
          sample > max_sample_value -> max_sample_value
          sample < min_sample_value -> min_sample_value
          true -> sample
        end
      end
    else
      max_sample_value = (1 <<< (8*sample_size)) - 1
      fn sample ->
        if sample > max_sample_value do max_sample_value else sample end
      end
    end
  end

  defp zip_longest(enums, acc \\ []) do
    {enums, zipped} = enums
      |> reject(&empty?/1)
      |> map_reduce([], fn [h|t], acc -> {t, [h | acc]} end)

    if zipped |> empty? do
      reverse acc
    else
      zipped = zipped |> reverse |> List.to_tuple
      zip_longest(enums, [zipped | acc])
    end
  end

  def chunk_binary(binary, chunk_size, acc \\ []) do
    case binary do
      <<chunk::binary-size(chunk_size)-unit(8)>> <> rest -> chunk_binary rest, chunk_size, [chunk | acc]
      _ -> reverse acc
    end
  end

  def mix(samples, mix_params, acc \\ 0)
  def mix([], %{format: format, clipper: clipper}, acc) do
    {:ok, sample} = acc |> clipper.() |> CapsHelper.value_to_sample(format)
    sample
  end
  def mix([h|t], %{format: format} = mix_params, acc) do
    {:ok, value} = h |> Raw.sample_to_value(format)
    mix t, mix_params, acc + value
  end
  def mix_params(format) do
    %{format: format, clipper: clipper_factory(format)}
  end

  @doc false
  def handle_buffer({:sink, %Membrane.Buffer{payload: payload}}, %{caps: %Raw{format: format}} = state) do
    {:ok, sample_size} = Raw.format_to_sample_size(format)
    mixed_payload = payload
      |> map(&chunk_binary &1, sample_size)
      |> zip_longest
      |> map(fn t -> t |> Tuple.to_list |> mix(mix_params format) end)

    {:ok, [{:send, {:source, %Membrane.Buffer{payload: mixed_payload}}}], state}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
