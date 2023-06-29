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
  @stream_format %RawAudio{
    channels: 2,
    sample_rate: 44_100,
    sample_format: :s24le
  }

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

  @tag :tmp_dir
  test "send `schedule_eos when mixer has one input pad", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure =
      [
        child(:mixer, Membrane.LiveAudioMixer)
        |> child(:file_sink, %Membrane.File.Sink{location: output_path})
      ] ++ add_audio_source(1)

    assert pipeline = Pipeline.start_link_supervised!(spec: structure)
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    Pipeline.message_child(pipeline, :mixer, :schedule_eos)

    structure = add_audio_source(2)

    Pipeline.execute_actions(pipeline, spec: structure)
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))
    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path)
  end

  @tag :tmp_dir
  test "send `schedule_eos when mixer has no input pad", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, Membrane.LiveAudioMixer)
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    assert pipeline = Pipeline.start_link_supervised!(spec: structure)
    Pipeline.message_child(pipeline, :mixer, :schedule_eos)

    structure = add_audio_source(1) ++ add_audio_source(2)

    Pipeline.execute_actions(pipeline, spec: structure)
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))
    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path)
  end

  @tag :tmp_dir
  test "raise when new input pad is added after eos", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)
    elements = create_elements(output_path, nil, true)
    links = create_links()

    assert pipeline = Pipeline.start_link_supervised!(spec: elements ++ links)
    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    structure = add_audio_source(3)

    Process.flag(:trap_exit, true)
    Pipeline.execute_actions(pipeline, spec: structure)

    assert_receive({:EXIT, ^pipeline, {:shutdown, :child_crash}})
  end

  @tag :tmp_dir
  test "raise when latency and stream_format is set to nil", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, %Membrane.LiveAudioMixer{latency: nil})
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    {:error, _error} = Pipeline.start(structure: structure)
  end

  @tag :tmp_dir
  test "manually start mixing before input pads are added", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, %Membrane.LiveAudioMixer{latency: nil, stream_format: @stream_format})
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    assert pipeline = Pipeline.start_link_supervised!(structure: structure)

    Pipeline.message_child(pipeline, :mixer, {:start_mixing, 0})

    # audio duration has to be equal or longer than 15 seconds
    # input audio has 10 seconds
    # thats why sleep is a little longer than 5 seconds
    Process.sleep(5_300)

    structure = add_audio_source(1) ++ add_audio_source(2)
    Pipeline.execute_actions(pipeline, spec: structure)

    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path, 15)
  end

  @tag :tmp_dir
  test "manually start mixing after input pads are added", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, %Membrane.LiveAudioMixer{latency: nil, stream_format: @stream_format})
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    assert pipeline = Pipeline.start_link_supervised!(structure: structure)

    structure = add_audio_source(1) ++ add_audio_source(2)
    Pipeline.execute_actions(pipeline, spec: structure)

    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))

    Pipeline.message_child(pipeline, :mixer, {:start_mixing, 0})

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path)
  end

  @tag :tmp_dir
  test "manually start mixing and schedule eos with no input pads", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, %Membrane.LiveAudioMixer{latency: nil, stream_format: @stream_format})
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    assert pipeline = Pipeline.start_link_supervised!(structure: structure)

    Pipeline.message_child(pipeline, :mixer, {:start_mixing, 0})

    # audio duration has to be equal or longer than 5 seconds
    # thats why sleep is a little longer than 5 seconds
    Process.sleep(5_300)

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)

    assert_end_of_stream(pipeline, :file_sink, :input, 1_000)

    check_output_duration(output_path, 5)
  end

  @tag :tmp_dir
  test "manually start mixing with schedule_eos sent at the beginning", %{tmp_dir: tmp_dir} do
    output_path = Path.join(tmp_dir, @output_file)

    structure = [
      child(:mixer, %Membrane.LiveAudioMixer{latency: nil, stream_format: @stream_format})
      |> child(:file_sink, %Membrane.File.Sink{location: output_path})
    ]

    assert pipeline = Pipeline.start_link_supervised!(structure: structure)

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)

    structure = add_audio_source(1) ++ add_audio_source(2)
    Pipeline.execute_actions(pipeline, spec: structure)

    Pipeline.message_child(pipeline, :mixer, {:start_mixing, 0})

    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))

    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path, 10)
  end

  defp add_audio_source(id) do
    [
      child({:file_src, id}, %Membrane.File.Source{location: @input_path_mp3})
      |> child({:decoder, id}, Membrane.MP3.MAD.Decoder)
      |> child({:parser, id}, Membrane.AudioMixer.Support.RawAudioParser)
      |> child({:realtimer, id}, Membrane.Realtimer)
      |> via_in(Pad.ref(:input, id))
      |> get_child(:mixer)
    ]
  end

  defp perform_test(structure, output_path) do
    assert pipeline = Pipeline.start_link_supervised!(spec: structure)
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 1))
    assert_start_of_stream(pipeline, :mixer, Pad.ref(:input, 2))

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    check_output_duration(output_path)
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

  defp check_output_duration(output_path, audio_duration \\ @audio_duration) do
    assert {:ok, output_file} = File.read(output_path)

    output_duration =
      byte_size(output_file)
      |> Membrane.RawAudio.bytes_to_time(@stream_format)
      |> Membrane.Time.as_seconds()
      |> Ratio.floor()

    assert output_duration == audio_duration
  end
end
