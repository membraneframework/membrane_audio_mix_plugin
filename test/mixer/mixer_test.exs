defmodule Membrane.AudioMixerTest do
  @moduledoc false

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @stream_format %RawAudio{
    channels: 2,
    sample_rate: 44_100,
    sample_format: :s24le
  }

  @output_file "output.raw"
  @input_path_mp3 Path.expand("../fixtures/mixer/input.mp3", __DIR__)
  @input_path_raw Path.expand("../fixtures/mixer/input-1.raw", __DIR__)

  @tag :tmp_dir
  test "mixer has its own stream format", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    elements = create_elements_with_decoders(output_path)
    links = create_links()

    perform_test(elements ++ links)
  end

  @tag :tmp_dir
  test "input stream format is RemoteStream", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    elements = [
      child(:file_sink, %Membrane.File.Sink{location: output_path}),
      child({:file_src, 1}, %Membrane.File.Source{location: @input_path_raw}),
      child({:file_src, 2}, %Membrane.File.Source{location: @input_path_raw}),
      child(:mixer, %Membrane.AudioMixer{prevent_clipping: false, stream_format: @stream_format})
    ]

    links = [
      get_child({:file_src, 1})
      |> get_child(:mixer)
      |> get_child(:file_sink),
      get_child({:file_src, 2})
      |> get_child(:mixer)
    ]

    perform_test(elements ++ links)
  end

  defp create_elements_with_decoders(output_path),
    do: [
      child(:mixer, %Membrane.AudioMixer{stream_format: @stream_format}),
      child({:file_src, 1}, %Membrane.File.Source{location: @input_path_mp3}),
      child({:file_src, 2}, %Membrane.File.Source{location: @input_path_mp3}),
      child({:parser, 1}, Membrane.AudioMixer.Support.RawAudioParser),
      child({:parser, 2}, Membrane.AudioMixer.Support.RawAudioParser),
      child({:decoder, 1}, Membrane.MP3.MAD.Decoder),
      child({:decoder, 2}, Membrane.MP3.MAD.Decoder),
      child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

  defp create_links(),
    do: [
      get_child({:file_src, 1})
      |> get_child({:decoder, 1})
      |> get_child({:parser, 1})
      |> get_child(:mixer)
      |> get_child(:file_sink),
      get_child({:file_src, 2})
      |> get_child({:decoder, 2})
      |> get_child({:parser, 2})
      |> get_child(:mixer)
    ]

  defp perform_test(spec) do
    assert pipeline = Pipeline.start_link_supervised!(spec: spec)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)
    Pipeline.terminate(pipeline)
  end
end
