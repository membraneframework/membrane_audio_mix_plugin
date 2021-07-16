# Membrane Audio Mixer Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_mixer_plugin.svg)](https://hex.pm/packages/membrane_audio_mixer_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_mixer_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_audio_mixer_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_audio_mixer_plugin)

Plugin providing an element mixing raw audio frames.

It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
{:membrane_audio_mixer_plugin, "~> 0.1.0"}
```

## Description

Provided element add samples from all pads and clip the result to maximum value for given format
to avoid overflow.

Mixer mixes only raw audio (PCM), so some parser may be needed to precede it in pipeline.

Audio format can be set as an element option or received through caps from input pads. All
caps received from input pads have to be identical and match ones in element option (if that 
option is different than nil).

Input pads can have offset - it tells how much silence should be added before first sample
from that pad. Offset have to be positive.

## Sample usage

```elixir
defmodule Mixing.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      file_src_1: %Membrane.File.Source{location: "/tmp/input_1.raw"},
      file_src_2: %Membrane.File.Source{location: "/tmp/input_2.raw"},
      mixer: %Membrane.AudioMixer{
        caps: %Caps{
              channels: 1,
              sample_rate: 16_000,
              format: :s16le
            }
      },
      converter: %Membrane.FFmpeg.SWResample.Converter{
        input_caps: %Caps{channels: 1, sample_rate: 16_000, format: :s16le},
        output_caps: %Caps{channels: 2, sample_rate: 48_000, format: :s16le}
      },
      player: Membrane.PortAudio.Sink
    ]

    links = [
      link(:file_src_1)
      |> to(:mixer)
      |> to(:converter)
      |> to(:player),

      link(:file_src_2)
      |> via_in(:input, options: [offset: Membrane.Time.milliseconds(5000)])
      |> to(:mixer),
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end
```

## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
