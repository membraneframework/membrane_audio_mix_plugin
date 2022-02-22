module Membrane.AudioMixer.Mixer.Native

state_type "State"

spec init(channels :: int, format :: unsigned, sample_rate :: int) :: {:ok :: label, state}

spec mix(buffers :: [payload], state) :: {:ok :: label, buffer :: payload, state}

spec flush(state) :: {:ok :: label, buffer :: payload, state}
