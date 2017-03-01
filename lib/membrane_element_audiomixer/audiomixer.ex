defmodule Membrane.Element.AudioMixer.MixerOptions do
end

defmodule Membrane.Element.AudioMixer.Mixer do

  import Enum
  use Bitwise
  use Membrane.Element.Base.Filter
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Element.AudioMixer.MixerOptions

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

  @source_pads [:sink0, :sink1, :sink2]

  def source_pads, do: @source_pads

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
  def handle_prepare(_) do
    {:ok}
  end

  @doc false
  def handle_caps({:sink, %Membrane.Caps.Audio.Raw{format: format} = caps}, state) do
    {:ok, sample_size} = Raw.format_to_sample_size(format)
    {:ok, %{state | sample_size: sample_size}}
  end

  @doc false
  def handle_buffer({:sink, %Membrane.Buffer{payload: payload} = buffer}, %{sample_size: sample_size} = state) do
    max_sample_value = (1 <<< (8*sample_size-1)) - 1
    min_sample_value = -(1 <<< (8*sample_size-1))
    result = payload
      |> map(
        fn e -> e
          |> :binary.bin_to_list
          |> chunk(sample_size)
          |> map(&:erlang.list_to_binary/1)
          |> map(&case &1 do <<s::little-signed-integer-size(sample_size)-unit(8)>> -> s end)
        end
      )
      |> zip
      |> map(&Tuple.to_list/1)
      |> map(&sum/1)
      |> map(&cond do
          &1 > max_sample_value -> max_sample_value
          &1 < min_sample_value -> min_sample_value
          true -> &1
        end)
      |> map(&<<&1::little-signed-integer-size(sample_size)-unit(8)>>)

    {:ok, result}
  end

  @doc false
  def handle_stop(state) do
    {:ok, state}
  end
end
