# Membrane Audio Mix Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_audio_mix_plugin.svg)](https://hex.pm/packages/membrane_audio_mix_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_audio_mix_plugin/)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_audio_mix_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_audio_mix_plugin)

Plugin providing elements for mixing and interleaving raw audio frames.

It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

Add the following line to your `deps` in `mix.exs`. Run `mix deps.get`.

```elixir
	{:membrane_audio_mix_plugin, "~> 0.12.0"}
```

## Description

Both elements operate only on raw audio (PCM), so some parser may be needed to precede them in a pipeline.

Audio format can be set as an element option or received through caps from input pads. All
caps received from input pads have to be identical and match ones in element option (if that
option is different from `nil`).

Input pads can have offset - it tells how much silence should be added before first sample
from that pad. Offset has to be positive.

All inputs have to be added before starting the pipeline and should not be changed
during mixer's or interleaver's work.

Mixing and interleaving is tested only for integer audio formats.

### Mixer

The Mixer adds samples from all pads. It has two strategies to deal with the overflow:
scaling down waves and clipping.

### Interleaver

This element joins several mono audio streams (with one channel) into one stream with interleaved channels.

If audio streams have different durations, all shorter streams are appended with silence to match the longest stream.

Each channel must be named by providing an input pad name and the channel layout using those names must be provided (see [usage example](#audiointerleaver)).

## Usage Example

### AudioMixer

```elixir
defmodule Mixing.Pipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, _options) do
    structure = [
      child({:file_src, 1}, %Membrane.File.Source{location: "/tmp/input_1.raw"})
      |> get_child(:mixer),

      child({:file_src, 2}, %Membrane.File.Source{location: "/tmp/input_2.raw"})
      |> via_in(:input, options: [offset: Membrane.Time.milliseconds(5000)])
      |> get_child(:mixer),

      child(:mixer, %Membrane.AudioMixer{
        caps: %Membrane.RawAudio{
          channels: 1,
          sample_rate: 16_000,
          sample_format: :s16le
        }
      }) 
      |> child(:converter, %Membrane.FFmpeg.SWResample.Converter{
        input_caps: %Membrane.RawAudio{channels: 1, sample_rate: 16_000, sample_format: :s16le},
        output_caps: %Membrane.RawAudio{channels: 2, sample_rate: 48_000, sample_format: :s16le}
      })
      |> child(:player, Membrane.PortAudio.Sink)
    ]

    {[spec: structure], %{}}
  end
end
```

### AudioInterleaver

```elixir
defmodule Interleave.Pipeline do
  use Membrane.Pipeline

  alias Membrane.File.{Sink, Source}

  @impl true
  def handle_init(_ctx, {path_to_wav_1, path_to_wav_2}) do
    structure = [
      child({:file, 1}, %Source{location: path_to_wav_1})
      |> child({:parser, 1}, Membrane.WAV.Parser)
      |> get_child(:interleaver),

      child({:file, 2}, %Source{location: path_to_wav_2})
      |> child({:parser, 2}, Membrane.WAV.Parser)
      |> get_child(:interleaver),


      child(:interleaver, %Membrane.AudioInterleaver{
        input_caps: %Membrane.RawAudio{
          channels: 1,
          sample_rate: 16_000,
          sample_format: :s16le
        },
        order: [:left, :right]
      })
      |> child(:file_sink, %Sink{location: "output.raw"})
    ]

    {[spec: structure], %{}}
  end
end

```

## Copyright and License

Copyright 2023, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane)

Licensed under the [Apache License, Version 2.0](LICENSE)
