ExUnit.start(capture_log: true)

defmodule Membrane.AudioMix.TestHelper do
  @moduledoc false
  alias Membrane.RawAudio

  @spec supported_stream_formats() :: [{integer(), integer(), atom()}]
  def supported_stream_formats(),
    do: [
      {1, 16_000, :s8},
      {1, 16_000, :s16le},
      {1, 16_000, :s24le},
      {1, 16_000, :s32le},
      {1, 16_000, :s16be},
      {1, 16_000, :s24be},
      {1, 16_000, :s32be},
      {1, 44_100, :s16le},
      {1, 44_100, :s16be},
      {2, 16_000, :s16le},
      {2, 16_000, :s16be},
      {6, 16_000, :s16le},
      {6, 16_000, :s16be}
    ]

  @spec generate_stream_formats([{integer(), integer(), atom()}]) :: [Raw.t()]
  def generate_stream_formats(stream_formats_contents) do
    Enum.map(
      stream_formats_contents,
      fn {channels, sample_rate, format} = _stream_formats ->
        %RawAudio{
          channels: channels,
          sample_rate: sample_rate,
          sample_format: format
        }
      end
    )
  end
end
