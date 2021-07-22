defmodule DoMixTest do
  @moduledoc """
  Tests for DoMix module. It contatins only one public function - `mix(buffers, caps)`, so tests
  check output of the mixing for serveral formats.

  Debugging: before every test, Membrane.Logger prints message with used caps. They can be seen
  only when particular test do not pass. In such case last debug message contains caps for
  which the test did not pass.
  """

  use ExUnit.Case

  import Membrane.AudioMixer.DoMix

  alias Membrane.Caps.Audio.Raw, as: Caps

  require Membrane.Logger

  defp test_for_caps(caps_contents, buffers, reference) do
    caps_contents
    |> generate_caps()
    |> Enum.each(fn caps ->
      Membrane.Logger.debug("caps: #{inspect(caps)}")
      assert reference == mix(buffers, caps)
    end)
  end

  defp generate_caps(caps_contents) do
    Enum.map(
      caps_contents,
      fn {channels, sample_rate, format} = _caps ->
        %Caps{
          channels: channels,
          sample_rate: sample_rate,
          format: format
        }
      end
    )
  end

  describe "DoMix should just sum bytes from inputs in simple cases" do
    defp test_for_several_caps(buffers, reference) do
      caps = [
        {1, 16000, :s8},
        {1, 16000, :u8},
        {1, 16000, :s16le},
        {1, 16000, :s24le},
        {1, 16000, :s32le},
        {1, 16000, :u16le},
        {1, 16000, :u24le},
        {1, 16000, :u32le},
        {1, 16000, :s16be},
        {1, 16000, :s24be},
        {1, 16000, :s32be},
        {1, 16000, :u16be},
        {1, 16000, :u24be},
        {1, 16000, :u32be},
        {1, 44100, :s16le},
        {1, 44100, :s16be},
        {2, 16000, :s16le},
        {2, 16000, :u16le},
        {2, 16000, :s16be},
        {2, 16000, :u16be},
        {6, 16000, :s16le},
        {6, 16000, :u16le},
        {6, 16000, :s16be},
        {6, 16000, :u16be}
      ]

      test_for_caps(caps, buffers, reference)
    end

    test "when 2 inputs have 0 bytes" do
      buffers = [<<>>, <<>>]
      reference = <<>>

      test_for_several_caps(buffers, reference)
    end

    test "when 2 inputs have 12 bytes" do
      buffers = [
        <<10, 205, 30, 40, 10, 130, 16, 78, 129, 0, 255, 0>>,
        <<240, 45, 40, 55, 99, 120, 239, 22, 71, 0, 0, 255>>
      ]

      reference = <<250, 250, 70, 95, 109, 250, 255, 100, 200, 0, 255, 255>>

      test_for_several_caps(buffers, reference)
    end

    test "when 3 inputs have 12 bytes" do
      buffers = [
        <<0, 255, 0, 0, 40, 10, 50, 175, 10, 20, 30, 30>>,
        <<0, 0, 255, 0, 40, 100, 70, 28, 80, 70, 60, 50>>,
        <<0, 0, 0, 255, 40, 15, 130, 52, 20, 30, 10, 47>>
      ]

      reference = <<0, 255, 255, 255, 120, 125, 250, 255, 110, 120, 100, 127>>

      test_for_several_caps(buffers, reference)
    end
  end

  describe "DoMix should work for little endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      caps = [
        {1, 16000, :s16le},
        {1, 16000, :s32le},
        {1, 44100, :s16le},
        {2, 16000, :s16le}
      ]

      buffers = [<<6, 80, 255, 255>>, <<250, 30, 255, 255>>]
      reference = <<0, 111, 254, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      caps = [
        {1, 16000, :s24le},
        {1, 44100, :s24le}
      ]

      buffers = [<<6, 255, 255>>, <<30, 255, 255>>]
      reference = <<36, 254, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly unsigned ones (4 bytes)" do
      caps = [
        {1, 16000, :u16le},
        {1, 16000, :u32le},
        {1, 44100, :u16le},
        {2, 16000, :u16le}
      ]

      buffers = [<<6, 80, 150, 180>>, <<250, 30, 240, 50>>]
      reference = <<0, 111, 134, 231>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly unsigned ones (3 bytes)" do
      caps = [
        {1, 16000, :u24le},
        {1, 44100, :u24le}
      ]

      buffers = [<<250, 255, 120>>, <<30, 0, 115>>]
      reference = <<24, 0, 236>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "DoMix should work for big endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      caps = [
        {1, 16000, :s16be},
        {1, 16000, :s32be},
        {1, 44100, :s16be},
        {2, 16000, :s16be}
      ]

      buffers = [<<255, 255, 80, 6>>, <<255, 255, 30, 250>>]
      reference = <<255, 254, 111, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      caps = [
        {1, 16000, :s24be},
        {1, 44100, :s24be}
      ]

      buffers = [<<255, 255, 6>>, <<255, 255, 30>>]
      reference = <<255, 254, 36>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly unsigned ones (4 bytes)" do
      caps = [
        {1, 16000, :u16be},
        {1, 16000, :u32be},
        {1, 44100, :u16be},
        {2, 16000, :u16be}
      ]

      buffers = [<<180, 150, 80, 6>>, <<50, 240, 30, 250>>]
      reference = <<231, 134, 111, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly unsigned ones (3 bytes)" do
      caps = [
        {1, 16000, :u24be},
        {1, 44100, :u24be}
      ]

      buffers = [<<120, 255, 250>>, <<115, 0, 30>>]
      reference = <<236, 0, 24>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "DoMix should work for values without endianness" do
    test "so mixes properly signed ones" do
      caps = [
        {1, 16000, :s8},
        {1, 44100, :s8},
        {2, 16000, :s8},
        {4, 16000, :s8}
      ]

      buffers = [<<15, 250, 215, 213>>, <<110, 255, 0, 37>>]
      reference = <<125, 249, 215, 250>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "DoMix should clip properly" do
    test "samples in :s8 format" do
      caps = [
        {1, 16000, :s8},
        {1, 44100, :s8},
        {2, 16000, :s8},
        {4, 16000, :s8}
      ]

      buffers = [<<80, 64, 128, 190>>, <<80, 64, 128, 190>>]
      reference = <<127, 127, 128, 128>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u8 format" do
      caps = [
        {1, 16000, :u8},
        {1, 44100, :u8},
        {2, 16000, :u8},
        {4, 16000, :u8}
      ]

      buffers = [<<255, 255, 128, 190>>, <<255, 1, 128, 190>>]
      reference = <<255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s16le format" do
      caps = [
        {1, 16000, :s16le},
        {1, 44100, :s16le},
        {2, 16000, :s16le}
      ]

      buffers = [<<255, 80, 255, 180>>, <<255, 80, 255, 180>>]
      reference = <<255, 127, 0, 128>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u16le format" do
      caps = [
        {1, 16000, :u16le},
        {1, 44100, :u16le},
        {2, 16000, :u16le}
      ]

      buffers = [<<255, 200, 0, 128>>, <<255, 150, 0, 128>>]
      reference = <<255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s16be format" do
      caps = [
        {1, 16000, :s16be},
        {1, 44100, :s16be},
        {2, 16000, :s16be}
      ]

      buffers = [<<80, 255, 180, 255>>, <<80, 255, 180, 255>>]
      reference = <<127, 255, 128, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u16be format" do
      caps = [
        {1, 16000, :u16be},
        {1, 44100, :u16be},
        {2, 16000, :u16be}
      ]

      buffers = [<<200, 255, 128, 0>>, <<150, 255, 128, 0>>]
      reference = <<255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s24le format" do
      caps = [
        {1, 16000, :s24le},
        {1, 44100, :s24le},
        {2, 16000, :s24le}
      ]

      buffers = [<<255, 255, 127, 255, 255, 150>>, <<255, 255, 127, 255, 255, 150>>]
      reference = <<255, 255, 127, 0, 0, 128>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u24le format" do
      caps = [
        {1, 16000, :u24le},
        {1, 44100, :u24le},
        {2, 16000, :u24le}
      ]

      buffers = [<<1, 0, 0, 255, 255, 255>>, <<255, 255, 255, 255, 255, 255>>]
      reference = <<255, 255, 255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s24be format" do
      caps = [
        {1, 16000, :s24be},
        {1, 44100, :s24be},
        {2, 16000, :s24be}
      ]

      buffers = [<<127, 255, 255, 150, 255, 255>>, <<127, 255, 255, 150, 255, 255>>]
      reference = <<127, 255, 255, 128, 0, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u24be format" do
      caps = [
        {1, 16000, :u24be},
        {1, 44100, :u24be},
        {2, 16000, :u24be}
      ]

      buffers = [<<0, 0, 1, 255, 255, 255>>, <<255, 255, 255, 255, 255, 255>>]
      reference = <<255, 255, 255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s32le format" do
      caps = [
        {1, 16000, :s32le},
        {1, 44100, :s32le},
        {2, 16000, :s32le}
      ]

      buffers = [
        <<255, 255, 255, 100, 255, 255, 255, 180>>,
        <<255, 255, 255, 100, 255, 255, 255, 180>>
      ]
      reference = <<255, 255, 255, 127, 0, 0, 0, 128>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u32le format" do
      caps = [
        {1, 16000, :u32le},
        {1, 44100, :u32le},
        {2, 16000, :u32le}
      ]

      buffers = [
        <<255, 255, 255, 200, 255, 255, 255, 255>>,
        <<255, 255, 255, 200, 1, 0, 0, 0>>
      ]
      reference = <<255, 255, 255, 255, 255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s32be format" do
      caps = [
        {1, 16000, :s32be},
        {1, 44100, :s32be},
        {2, 16000, :s32be}
      ]

      buffers = [
        <<100, 255, 255, 255, 180, 255, 255, 255>>,
        <<100, 255, 255, 255, 180, 255, 255, 255>>
      ]
      reference = <<127, 255, 255, 255, 128, 0, 0, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :u32be format" do
      caps = [
        {1, 16000, :u32be},
        {1, 44100, :u32be},
        {2, 16000, :u32be}
      ]

      buffers = [
        <<200, 255, 255, 255, 255, 255, 255, 255>>,
        <<200, 255, 255, 255, 0, 0, 0, 1>>
      ]
      reference = <<255, 255, 255, 255, 255, 255, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end
  end
end
