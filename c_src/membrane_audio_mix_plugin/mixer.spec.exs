module Membrane.AudioMixer.Mixer.Native

type(
  params :: %Params{
    sample_size: int,
    sample_max: int,
    sample_min: int
  }
)

state_type "State"

spec init(params :: params) :: {:ok :: label, state}

spec mix(buffers :: [payload], state) :: {:ok, buffer :: payload, state}

spec flush(state) :: {:ok, buffer :: payload, state}
