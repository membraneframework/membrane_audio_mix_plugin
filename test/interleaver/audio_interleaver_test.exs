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

  test "splits binaries in chunks" do
    assert DoInterleave.split_in_chunks(<<1, 2, 3, 4>>, 2) == [<<1, 2>>, <<3, 4>>]
    assert DoInterleave.split_in_chunks(<<1, 2, 3, 4>>, 3) == [<<1, 2, 3>>, <<4>>]
    assert DoInterleave.split_in_chunks(<<1, 2, 3>>, 1) == [<<1>>, <<2>>, <<3>>]
    assert DoInterleave.split_in_chunks(<<1>>, 1) == [<<1>>]
    assert DoInterleave.split_in_chunks(<<>>, 1) == [<<>>]
  end
end