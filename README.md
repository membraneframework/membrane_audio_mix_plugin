# Membrane Audio Mixer Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_mixer_plugin.svg)](https://hex.pm/packages/membrane_audio_mixer_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_mixer_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_audio_mixer_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_audio_mixer_plugin)

Plugin providing elements for mixing and interleaving raw audio frames.

It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
{:membrane_audio_mixer_plugin, "~> 0.1.0"}
```

## Description

Both elements operate only on raw audio (PCM), so some parser may be needed to precede them in a pipeline.

Audio format can be set as an element option or received through caps from input pads. All
caps received from input pads have to be identical and match ones in element option (if that 
option is different from `nil`).

All inputs have to be added before starting the pipeline and should not be changed
during mixer's work.

Mixing and interleaving is tested only for integer audio formats.
### Mixer

The Mixer adds samples from all pads and clips the result to the maximum value for given 
format to avoid overflow.

Input pads can have offset - it tells how much silence should be added before first sample
from that pad. Offset has to be positive.
### Interleaver

This element joins several mono audio streams (with one channel) into one stream with interleaved channels.

If audio streams have different size, longer stream is clipped.

Input pads have to be named by the user, and interleaving order must be provided (see example usage).

## Usage Example
### AudioMixer
```elixir
defmodule Mixing.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_) do
    children = [
      file_src_1: %Membrane.File.Source{location: "/tmp/input_1.raw"},
      file_src_2: %Membrane.File.Source{location: "/tmp/input_2.raw"},
      mixer: %Membrane.AudioMixer{
        caps: %Membrane.Caps.Audio.Raw{
          channels: 1,
          sample_rate: 16_000,
          format: :s16le
        }
      },
      converter: %Membrane.FFmpeg.SWResample.Converter{
        input_caps: %Membrane.Caps.Audio.Raw{channels: 1, sample_rate: 16_000, format: :s16le},
        output_caps: %Membrane.Caps.Audio.Raw{channels: 2, sample_rate: 48_000, format: :s16le}
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
      |> to(:mixer)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end
```
### AudioInterleaver
```elixir
defmodule Interleave.Pipeline do
  use Membrane.Pipeline

  alias Membrane.File.{Sink, Source}

  @impl true
  def handle_init({path_to_wav_1, path_to_wav_2}) do
    children = %{
      file_1: %Source{location: path_to_wav_1},
      file_2: %Source{location: path_to_wav_2},
      parser_1: Membrane.WAV.Parser,
      parser_2: Membrane.WAV.Parser,
      interleaver: %Membrane.AudioInterleaver{
        input_caps: %Membrane.Caps.Audio.Raw{
          channels: 1,
          sample_rate: 16_000,
          format: :s16le
        },
        order: [:left, :right]
      },
      file_sink: %Sink{location: "output.raw"}
    }

    links = [
      link(:file_1)
      |> to(:parser_1)
      |> via_in(Pad.ref(:input, :left))
      |> to(:interleaver),
      link(:file_2)
      |> to(:parser_2)
      |> via_in(Pad.ref(:input, :right))
      |> to(:interleaver),
      link(:interleaver)
      |> to(:file_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end

```

## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
