defmodule Membrane.AudioMixer.DeclipperTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Membrane.AudioMixer.Declipper

  require Membrane.Logger

  alias Membrane.AudioMix.TestHelper
  alias Membrane.AudioMixer.Declipper.State

  defp test_for_caps(caps_contents, buffers, reference) do
    caps_contents
    |> TestHelper.generate_caps()
    |> Enum.each(fn caps ->
      Membrane.Logger.debug("caps: #{inspect(caps)}")
      {result, %State{queue: queue}} = mix(buffers, true, caps, %State{})
      assert [] == queue
      assert reference == result
    end)
  end

  describe "Declipper should just sum bytes from inputs in simple cases" do
    defp test_for_several_caps(buffers, reference) do
      caps = [
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

  describe "Declipper should work for little endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      caps = [
        {1, 16_000, :s16le},
        {1, 16_000, :s32le},
        {1, 44_100, :s16le},
        {2, 16_000, :s16le}
      ]

      buffers = [<<6, 80, 255, 255>>, <<250, 30, 255, 255>>]
      reference = <<0, 111, 254, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      caps = [
        {1, 16_000, :s24le},
        {1, 44_100, :s24le}
      ]

      buffers = [<<6, 255, 255>>, <<30, 255, 255>>]
      reference = <<36, 254, 255>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "Declipper should work for big endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      caps = [
        {1, 16_000, :s16be},
        {1, 16_000, :s32be},
        {1, 44_100, :s16be},
        {2, 16_000, :s16be}
      ]

      buffers = [<<255, 255, 80, 6>>, <<255, 255, 30, 250>>]
      reference = <<255, 254, 111, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      caps = [
        {1, 16_000, :s24be},
        {1, 44_100, :s24be}
      ]

      buffers = [<<255, 255, 6>>, <<255, 255, 30>>]
      reference = <<255, 254, 36>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "Declipper should work for values without endianness" do
    test "so mixes properly signed ones" do
      caps = [
        {1, 16_000, :s8},
        {1, 44_100, :s8},
        {2, 16_000, :s8},
        {4, 16_000, :s8}
      ]

      buffers = [<<15, 250, 215, 213>>, <<110, 255, 0, 37>>]
      reference = <<125, 249, 215, 250>>

      test_for_caps(caps, buffers, reference)
    end
  end

  describe "Declipper should scale properly" do
    test "samples in :s8 format" do
      caps = [
        {1, 16_000, :s8},
        {1, 44_100, :s8},
        {2, 16_000, :s8},
        {4, 16_000, :s8}
      ]

      buffers = [<<30, 32, 128, 190>>, <<30, 32, 128, 190>>]
      reference = <<60, 64, 128, 190>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s16le format" do
      caps = [
        {1, 16_000, :s16le},
        {1, 44_100, :s16le},
        {2, 16_000, :s16le}
      ]

      buffers = [<<255, 80, 255, 2, 255, 180>>, <<255, 80, 255, 2, 255, 180>>]
      reference = <<255, 127, 188, 4, 0, 128>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s16be format" do
      caps = [
        {1, 16_000, :s16be},
        {1, 44_100, :s16be},
        {2, 16_000, :s16be}
      ]

      buffers = [<<80, 255, 180, 255>>, <<80, 255, 180, 255>>]
      reference = <<127, 255, 128, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s24le format" do
      caps = [
        {1, 16_000, :s24le},
        {1, 44_100, :s24le},
        {2, 16_000, :s24le}
      ]

      buffers = [
        <<0, 0, 128, 254, 255, 255>>,
        <<0, 0, 128, 254, 255, 255>>,
        <<0, 0, 128, 251, 255, 255>>,
        <<0, 0, 128, 251, 255, 255>>
      ]

      reference = <<0, 0, 128, 253, 255, 255>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s24be format" do
      caps = [
        {1, 16_000, :s24be},
        {1, 44_100, :s24be},
        {2, 16_000, :s24be}
      ]

      buffers = [
        <<128, 0, 0, 255, 255, 254>>,
        <<128, 0, 0, 255, 255, 254>>,
        <<128, 0, 0, 255, 255, 251>>,
        <<128, 0, 0, 255, 255, 251>>
      ]

      reference = <<128, 0, 0, 255, 255, 253>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s32le format" do
      caps = [
        {1, 16_000, :s32le},
        {1, 44_100, :s32le},
        {2, 16_000, :s32le}
      ]

      buffers = [
        <<255, 255, 255, 127, 0, 1, 5, 0>>,
        <<255, 255, 255, 127, 100, 1, 10, 0>>,
        <<255, 255, 255, 127, 200, 1, 5, 0>>,
        <<255, 255, 255, 127, 200, 1, 40, 0>>,
        <<255, 255, 255, 127, 100, 1, 0, 0>>,
        <<255, 255, 255, 127, 0, 7, 0, 0>>
      ]

      reference = <<255, 255, 255, 127, 100, 2, 10, 0>>

      test_for_caps(caps, buffers, reference)
    end

    test "samples in :s32be format" do
      caps = [
        {1, 16_000, :s32be},
        {1, 44_100, :s32be},
        {2, 16_000, :s32be}
      ]

      buffers = [
        <<127, 255, 255, 255, 0, 1, 5, 0>>,
        <<127, 255, 255, 255, 0, 1, 10, 200>>,
        <<127, 255, 255, 255, 0, 1, 5, 200>>,
        <<127, 255, 255, 255, 0, 1, 40, 200>>,
        <<127, 255, 255, 255, 0, 1, 0, 0>>,
        <<127, 255, 255, 255, 0, 7, 0, 0>>
      ]

      reference = <<127, 255, 255, 255, 0, 2, 10, 100>>

      test_for_caps(caps, buffers, reference)
    end
  end
end
