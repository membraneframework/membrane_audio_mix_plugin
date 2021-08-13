defmodule Membrane.AudioInterleaverTest do
  @moduledoc """
  Tests for DoMix module. It contatins only one public function - `mix(buffers, caps)`, so tests
  check output of the mixing for serveral formats.

  Debugging: before every test, Membrane.Logger prints message with used caps. They can be seen
  only when particular test do not pass. In such case last debug message contains caps for
  which the test did not pass.
  """

  use ExUnit.Case, async: true

  import Membrane.AudioInterleaver
  import Membrane.AudioMixer.DoInterleave

  alias Membrane.AudioInterleaver
  alias Membrane.AudioMixer.DoInterleave

  require Membrane.Logger

  test "splits binaries in reversed chunks" do
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3, 4>>, 2) == [<<3, 4>>, <<1, 2>>]
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3, 4>>, 3) == [<<4>>, <<1, 2, 3>>]
    assert DoInterleave.to_chunks_reversed(<<1, 2, 3>>, 1) == [<<3>>, <<2>>, <<1>>]
    assert DoInterleave.to_chunks_reversed(<<1>>, 1) == [<<1>>]
    assert DoInterleave.to_chunks_reversed(<<>>, 1) == [<<>>]
  end

  test "interleave binaries" do
    payload1 = <<227, 2, 3, 4, 5, 6>>
    payload2 = <<7, 8, 9, 10, 11, 12>>
    payload3 = <<10, 20, 30, 40, 50, 60>>

    assert do_interleave([payload1, payload2], 2) ==
             <<227, 2, 7, 8, 3, 4, 9, 10, 5, 6, 11, 12>>

    assert do_interleave(
             [payload1, payload2, payload3],
             2
           ) ==
             <<227, 2, 7, 8, 10, 20, 3, 4, 9, 10, 30, 40, 5, 6, 11, 12, 50, 60>>

    assert do_interleave(
             [payload1, payload2, payload3],
             3
           ) ==
             <<227, 2, 3, 7, 8, 9, 10, 20, 30, 4, 5, 6, 10, 11, 12, 40, 50, 60>>
  end
end
