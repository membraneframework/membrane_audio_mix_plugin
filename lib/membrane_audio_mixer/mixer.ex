defmodule Membrane.AudioMixer.Mixer do
  @moduledoc false

  alias Membrane.Caps.Audio.Raw

  @type state_t :: any()

  @doc """
  Initializes the mixer's state.
  """
  @callback init(caps :: Raw.t()) :: state_t()

  @doc """
  Mixes `buffers` to one buffer. Given buffers should have equal sizes.
  """
  @callback mix(buffers :: [binary()], state :: state_t()) ::
              {buffer :: binary(), state :: state_t()}

  @doc """
  Forces mixer to flush the remaining buffers.
  """
  @callback flush(state :: state_t()) ::
              {buffer :: binary(), state :: state_t()}
end
