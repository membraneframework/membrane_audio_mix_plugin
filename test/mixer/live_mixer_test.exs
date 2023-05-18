defmodule Membrane.LiveAudioMixerTest do
  @moduledoc false

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline
  alias Membrane.Time

  @input_path_mp3 Path.expand("../fixtures/mixer/input.mp3", __DIR__)
  @output_file "output.raw"
  @audio_duration 10
  @latency Time.milliseconds(150)

  @tag :tmp_dir
  test "creates 10 sec stream even when a lot of packets are lost", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    elements = create_elements(output_path, nil, true)
    links = create_links()

    perform_test(elements ++ links, output_path)
  end

  @tag :tmp_dir
  test "creates 10 sec stream even when a lot of packets are late", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    elements = create_elements(output_path, @latency, false)
    links = create_links()

    perform_test(elements ++ links, output_path)
  end

  defp create_elements(output_path, latency, drop?),
    do: [
      child(:mixer, Membrane.LiveAudioMixer),
      child({:file_src, 1}, %Membrane.File.Source{location: @input_path_mp3}),
      child({:file_src, 2}, %Membrane.File.Source{location: @input_path_mp3}),
      child({:parser, 1}, Membrane.AudioMixer.Support.RawAudioParser),
      child({:parser, 2}, Membrane.AudioMixer.Support.RawAudioParser),
      child({:network_sim, 1}, %Membrane.AudioMixer.Support.NetworkSimulator{
        latency: latency,
        drop_every_other_packet: drop?
      }),
      child({:network_sim, 2}, %Membrane.AudioMixer.Support.NetworkSimulator{
        latency: latency,
        drop_every_other_packet: drop?
      }),
      child({:realtimer, 1}, Membrane.Realtimer),
      child({:realtimer, 2}, Membrane.Realtimer),
      child({:decoder, 1}, Membrane.MP3.MAD.Decoder),
      child({:decoder, 2}, Membrane.MP3.MAD.Decoder),
      child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

  defp create_links(),
    do: [
      get_child({:file_src, 1})
      |> get_child({:decoder, 1})
      |> get_child({:parser, 1})
      |> get_child({:realtimer, 1})
      |> get_child({:network_sim, 1})
      |> via_in(Pad.ref(:input, 1))
      |> get_child(:mixer)
      |> get_child(:file_sink),
      get_child({:file_src, 2})
      |> get_child({:decoder, 2})
      |> get_child({:parser, 2})
      |> get_child({:realtimer, 2})
      |> get_child({:network_sim, 2})
      |> via_in(Pad.ref(:input, 2))
      |> get_child(:mixer)
    ]

  defp perform_test(structure, output_path) do
    assert pipeline = Pipeline.start_link_supervised!(structure: structure)

    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    assert {:ok, output_file} = File.read(output_path)

    stream_format = %RawAudio{
      channels: 2,
      sample_rate: 44_100,
      sample_format: :s24le
    }

    output_duration =
      byte_size(output_file)
      |> Membrane.RawAudio.bytes_to_time(stream_format)
      |> Membrane.Time.as_seconds()
      |> Ratio.floor()

    assert output_duration == @audio_duration
  end
end
