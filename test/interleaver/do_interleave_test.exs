defmodule Membrane.DdInterleaveTest do
  @moduledoc """
  Tests for DoInterleave module.
  """

  use ExUnit.Case, async: true

  import Membrane.AudioMixer.DoInterleave

  alias Membrane.AudioMixer.DoInterleave

  require Membrane.Logger

  describe "DoInterleaver interleave should" do
    defp to_pad(key, queue, end_of_stream \\ false) do
      {{Membrane.Pad, :input, key}, %{end_of_stream: false, queue: queue}}
    end

    test "correctly interleave and update queues" do
      pads =
        Map.new([
          to_pad(1, <<1, 2, 3, 4, 5, 6, 7, 8>>),
          to_pad(2, <<90, 100, 110, 120, 130, 140, 150, 160>>)
        ])

      order = [1, 2]
      bytes_per_channel = 4

      interleaved1 = <<1, 90, 2, 100, 3, 110, 4, 120>>
      interleaved2 = <<1, 2, 90, 100, 3, 4, 110, 120>>
      interleaved3 = <<1, 2, 3, 90, 100, 110, 4, 120>>
      interleaved4 = <<1, 2, 3, 4, 90, 100, 110, 120>>

      new_pads = Map.new([to_pad(1, <<5, 6, 7, 8>>), to_pad(2, <<130, 140, 150, 160>>)])

      expected1 = {interleaved1, new_pads}
      expected2 = {interleaved2, new_pads}
      expected3 = {interleaved3, new_pads}
      expected4 = {interleaved4, new_pads}

      assert expected1 == DoInterleave.interleave(bytes_per_channel, 1, pads, order)
      assert expected2 == DoInterleave.interleave(bytes_per_channel, 2, pads, order)
      assert expected3 == DoInterleave.interleave(bytes_per_channel, 3, pads, order)
      assert expected4 == DoInterleave.interleave(bytes_per_channel, 4, pads, order)
    end

    test "interleave in correct order" do
      pads =
        Map.new([
          to_pad(1, <<1, 2, 3, 4, 5, 6, 7, 8>>),
          to_pad(2, <<90, 100, 110, 120, 130, 140, 150, 160>>)
        ])

      order = [2, 1]
      bytes_per_channel = 4

      interleaved1 = <<90, 1, 100, 2, 110, 3, 120, 4>>
      interleaved2 = <<90, 100, 1, 2, 110, 120, 3, 4>>

      new_pads = Map.new([to_pad(1, <<5, 6, 7, 8>>), to_pad(2, <<130, 140, 150, 160>>)])

      expected1 = {interleaved1, new_pads}
      expected2 = {interleaved2, new_pads}

      assert expected1 == DoInterleave.interleave(bytes_per_channel, 1, pads, order)
      assert expected2 == DoInterleave.interleave(bytes_per_channel, 2, pads, order)
    end
  end

  test "interleave binaries" do
    payload1 = <<227, 2, 3, 4, 5, 6>>
    payload2 = <<7, 8, 9, 10, 11, 12>>
    payload3 = <<10, 20, 30, 40, 50, 60>>

    assert interleave_binaries([payload1, payload2], 2) ==
             <<227, 2, 7, 8, 3, 4, 9, 10, 5, 6, 11, 12>>

    assert interleave_binaries(
             [payload1, payload2, payload3],
             2
           ) ==
             <<227, 2, 7, 8, 10, 20, 3, 4, 9, 10, 30, 40, 5, 6, 11, 12, 50, 60>>

    assert interleave_binaries(
             [payload1, payload2, payload3],
             3
           ) ==
             <<227, 2, 3, 7, 8, 9, 10, 20, 30, 4, 5, 6, 10, 11, 12, 40, 50, 60>>
  end

  test "split binaries in reversed chunks" do
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3, 4>>, 2) == [<<3, 4>>, <<1, 2>>]
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3, 4>>, 3) == [<<4>>, <<1, 2, 3>>]
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3>>, 1) == [<<3>>, <<2>>, <<1>>]
    assert DoInterleave.to_chunks_reversed(<<1>>, 1) == [<<1>>]
    assert DoInterleave.to_chunks_reversed(<<>>, 1) == [<<>>]
  end
end
