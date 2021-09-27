defmodule Membrane.AudioMixer.Mixer do
  @moduledoc false

  alias Membrane.Caps.Audio.Raw

  @type state_t :: any()

  @doc """
  Initializes the mixer's state.
  """
  @callback init() :: state_t()

  @doc """
  Mixes `buffers` to one buffer. Given buffers should have equal sizes. It uses information about
  samples provided in `caps`.
  """
  @callback mix(buffers :: [binary()], caps :: Raw.t(), state :: state_t()) ::
              {buffers :: binary(), state :: state_t()}

  @doc """
  Forces mixer to flush the remaining buffers. It uses information about samples provided in `caps`.
  """
  @callback flush(caps :: Raw.t(), state :: state_t()) ::
              {buffers :: binary(), state :: state_t()}
end
