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
end
