defmodule Membrane.AudioMixer.AdderTest do
  @moduledoc """
  Tests for Adder module. It contatins only one public function - `mix(buffers, stream_format)`, so tests
  check output of the mixing for serveral formats.

  Debugging: before every test, Membrane.Logger prints message with used stream_format. They can be seen
  only when particular test do not pass. In such case last debug message contains stream_format for
  which the test did not pass.
  """

  use ExUnit.Case, async: true

  import Membrane.AudioMixer.Adder

  require Membrane.Logger

  alias Membrane.AudioMix.TestHelper

  defp test_for_stream_format(stream_format_contents, buffers, reference) do
    stream_format_contents
    |> TestHelper.generate_stream_formats()
    |> Enum.each(fn stream_format ->
      state = init(stream_format)
      Membrane.Logger.debug("stream_format: #{inspect(stream_format)}")
      assert {reference, state} == mix(buffers, state)
    end)
  end

  describe "Adder should just sum bytes from inputs in simple cases" do
    defp test_for_several_stream_format(buffers, reference) do
      test_for_stream_format(TestHelper.supported_stream_formats(), buffers, reference)
    end

    test "when 2 inputs have 0 bytes" do
      buffers = [<<>>, <<>>]
      reference = <<>>

      test_for_several_stream_format(buffers, reference)
    end

    test "when 2 inputs have 12 bytes" do
      buffers = [
        <<10, 205, 30, 40, 10, 130, 16, 78, 129, 0, 255, 0>>,
        <<240, 45, 40, 55, 99, 120, 239, 22, 71, 0, 0, 255>>
      ]

      reference = <<250, 250, 70, 95, 109, 250, 255, 100, 200, 0, 255, 255>>

      test_for_several_stream_format(buffers, reference)
    end

    test "when 3 inputs have 12 bytes" do
      buffers = [
        <<0, 255, 0, 0, 40, 10, 50, 175, 10, 20, 30, 30>>,
        <<0, 0, 255, 0, 40, 100, 70, 28, 80, 70, 60, 50>>,
        <<0, 0, 0, 255, 40, 15, 130, 52, 20, 30, 10, 47>>
      ]

      reference = <<0, 255, 255, 255, 120, 125, 250, 255, 110, 120, 100, 127>>

      test_for_several_stream_format(buffers, reference)
    end
  end

  describe "Adder should work for little endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      stream_format = [
        {1, 16_000, :s16le},
        {1, 16_000, :s32le},
        {1, 44_100, :s16le},
        {2, 16_000, :s16le}
      ]

      buffers = [<<6, 80, 255, 255>>, <<250, 30, 255, 255>>]
      reference = <<0, 111, 254, 255>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      stream_format = [
        {1, 16_000, :s24le},
        {1, 44_100, :s24le}
      ]

      buffers = [<<6, 255, 255>>, <<30, 255, 255>>]
      reference = <<36, 254, 255>>

      test_for_stream_format(stream_format, buffers, reference)
    end
  end

  describe "Adder should work for big endian values" do
    test "so mixes properly signed ones (4 bytes)" do
      stream_format = [
        {1, 16_000, :s16be},
        {1, 16_000, :s32be},
        {1, 44_100, :s16be},
        {2, 16_000, :s16be}
      ]

      buffers = [<<255, 255, 80, 6>>, <<255, 255, 30, 250>>]
      reference = <<255, 254, 111, 0>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "so mixes properly signed ones (3 bytes)" do
      stream_format = [
        {1, 16_000, :s24be},
        {1, 44_100, :s24be}
      ]

      buffers = [<<255, 255, 6>>, <<255, 255, 30>>]
      reference = <<255, 254, 36>>

      test_for_stream_format(stream_format, buffers, reference)
    end
  end

  describe "Adder should work for values without endianness" do
    test "so mixes properly signed ones" do
      stream_format = [
        {1, 16_000, :s8},
        {1, 44_100, :s8},
        {2, 16_000, :s8},
        {4, 16_000, :s8}
      ]

      buffers = [<<15, 250, 215, 213>>, <<110, 255, 0, 37>>]
      reference = <<125, 249, 215, 250>>

      test_for_stream_format(stream_format, buffers, reference)
    end
  end

  describe "Adder should clip properly" do
    test "samples in :s8 format" do
      stream_format = [
        {1, 16_000, :s8},
        {1, 44_100, :s8},
        {2, 16_000, :s8},
        {4, 16_000, :s8}
      ]

      buffers = [<<80, 64, 128, 190>>, <<80, 64, 128, 190>>]
      reference = <<127, 127, 128, 128>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s16le format" do
      stream_format = [
        {1, 16_000, :s16le},
        {1, 44_100, :s16le},
        {2, 16_000, :s16le}
      ]

      buffers = [<<255, 80, 255, 180>>, <<255, 80, 255, 180>>]
      reference = <<255, 127, 0, 128>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s16be format" do
      stream_format = [
        {1, 16_000, :s16be},
        {1, 44_100, :s16be},
        {2, 16_000, :s16be}
      ]

      buffers = [<<80, 255, 180, 255>>, <<80, 255, 180, 255>>]
      reference = <<127, 255, 128, 0>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s24le format" do
      stream_format = [
        {1, 16_000, :s24le},
        {1, 44_100, :s24le},
        {2, 16_000, :s24le}
      ]

      buffers = [<<255, 255, 127, 255, 255, 150>>, <<255, 255, 127, 255, 255, 150>>]
      reference = <<255, 255, 127, 0, 0, 128>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s24be format" do
      stream_format = [
        {1, 16_000, :s24be},
        {1, 44_100, :s24be},
        {2, 16_000, :s24be}
      ]

      buffers = [<<127, 255, 255, 150, 255, 255>>, <<127, 255, 255, 150, 255, 255>>]
      reference = <<127, 255, 255, 128, 0, 0>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s32le format" do
      stream_format = [
        {1, 16_000, :s32le},
        {1, 44_100, :s32le},
        {2, 16_000, :s32le}
      ]

      buffers = [
        <<255, 255, 255, 100, 255, 255, 255, 180>>,
        <<255, 255, 255, 100, 255, 255, 255, 180>>
      ]

      reference = <<255, 255, 255, 127, 0, 0, 0, 128>>

      test_for_stream_format(stream_format, buffers, reference)
    end

    test "samples in :s32be format" do
      stream_format = [
        {1, 16_000, :s32be},
        {1, 44_100, :s32be},
        {2, 16_000, :s32be}
      ]

      buffers = [
        <<100, 255, 255, 255, 180, 255, 255, 255>>,
        <<100, 255, 255, 255, 180, 255, 255, 255>>
      ]

      reference = <<127, 255, 255, 255, 128, 0, 0, 0>>

      test_for_stream_format(stream_format, buffers, reference)
    end
  end

  describe "Adder should" do
    test "flush properly" do
      TestHelper.supported_stream_formats()
      |> TestHelper.generate_stream_formats()
      |> Enum.each(fn stream_format ->
        state = init(stream_format)
        assert flush(state) == {<<>>, state}
      end)
    end
  end
end
