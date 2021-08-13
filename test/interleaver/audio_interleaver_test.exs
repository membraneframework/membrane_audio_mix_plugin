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
    assert do_interleave([<<227, 2, 3, 4, 5, 6>>, <<7, 8, 9, 10, 11, 12>>], 2) ==
             <<227, 2, 7, 8, 3, 4, 9, 10, 5, 6, 11, 12>>
  end
end
