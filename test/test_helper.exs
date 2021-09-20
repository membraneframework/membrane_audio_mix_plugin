ExUnit.start(capture_log: true)

defmodule Membrane.AudioMix.TestHelper do
  @moduledoc false
  alias Membrane.Caps.Audio.Raw

  @spec generate_caps([{integer(), integer(), atom()}]) :: [Raw.t()]
  def generate_caps(caps_contents) do
    Enum.map(
      caps_contents,
      fn {channels, sample_rate, format} = _caps ->
        %Raw{
          channels: channels,
          sample_rate: sample_rate,
          format: format
        }
      end
    )
  end
end
