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
      fn sample -> cond do
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

  @doc false
  def handle_buffer({:sink, %Membrane.Buffer{payload: payload} = buffer}, %{caps: %Raw{format: format} = caps} = state) do
    {:ok, sample_size} = Raw.format_to_sample_size(format)
    clipper = clipper_factory(format)
    result = payload
      |> map(
        fn e -> e
          |> :binary.bin_to_list
          |> chunk(sample_size)
          |> map(&:binary.list_to_bin/1)
          |> map(&Raw.sample_to_value!(&1, format))
        end
      )
      |> zip
      |> map(&Tuple.to_list/1)
      |> map(&sum/1)
      |> map(clipper)
      |> map(&CapsHelper.value_to_sample!(&1, format))

    {:ok, result}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
