defmodule Membrane.CommonMixerTest do
  @moduledoc false

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @input_path_1 Path.expand("../fixtures/mixer/input-1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/mixer/input-2.raw", __DIR__)

  describe "two tracks with the same size" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-same-size.raw")
      preventer_reference_path = expand_path("reference-same-size-preventer.raw")
      base_elements = create_base_elements([@input_path_1, @input_path_1], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        preventer_reference_path: preventer_reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      preventer_reference_path: preventer_reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, preventer_reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      preventer_reference_path: preventer_reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, preventer_reference_path, output_path)
    end
  end

  describe "two tracks with different sizes" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-different-size.raw")
      base_elements = create_base_elements([@input_path_1, @input_path_2], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path)
    end
  end

  describe "tracks when the shorter one has an offset" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-offset-first.raw")
      base_elements = create_base_elements([@input_path_1, @input_path_2], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1), options: [offset: Membrane.Time.microseconds(125)])
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2))
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path)
    end
  end

  describe "tracks when the longer one has an offset" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-offset-second.raw")
      base_elements = create_base_elements([@input_path_1, @input_path_2], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2), options: [offset: Membrane.Time.microseconds(250)])
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path)
    end
  end

  describe "tracks when both have offsets" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-offsets-both.raw")
      base_elements = create_base_elements([@input_path_1, @input_path_2], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1), options: [offset: Membrane.Time.microseconds(500)])
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2), options: [offset: Membrane.Time.microseconds(125)])
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path)
    end
  end

  describe "three tracks" do
    setup do
      output_path = prepare_output()
      reference_path = expand_path("reference-three.raw")

      base_elements =
        create_base_elements([@input_path_1, @input_path_1, @input_path_2], output_path)

      links = [
        get_child({:file_src, 1})
        |> get_child({:parser, 1})
        |> via_in(Pad.ref(:input, 1))
        |> get_child(:mixer)
        |> get_child(:file_sink),
        get_child({:file_src, 2})
        |> get_child({:parser, 2})
        |> via_in(Pad.ref(:input, 2), options: [offset: Membrane.Time.microseconds(250)])
        |> get_child(:mixer),
        get_child({:file_src, 3})
        |> get_child({:parser, 3})
        |> via_in(Pad.ref(:input, 3), options: [offset: Membrane.Time.microseconds(125)])
        |> get_child(:mixer)
      ]

      %{
        output_path: output_path,
        reference_path: reference_path,
        base_elements: base_elements,
        links: links
      }
    end

    test "LiveAudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_live_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path, true)
    end

    test "AudioMixer", %{
      output_path: output_path,
      reference_path: reference_path,
      base_elements: base_elements,
      links: links
    } do
      {mixer, preventer_mixer, native_mixer} = get_offline_mixers()

      elements =
        {base_elements ++ mixer, base_elements ++ preventer_mixer, base_elements ++ native_mixer}

      perform_test(elements, links, reference_path, reference_path, output_path)
    end
  end

  defp expand_path(file_name) do
    Path.expand("../fixtures/mixer/#{file_name}", __DIR__)
  end

  defp prepare_output() do
    output_path = expand_path("output.raw")

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  defp create_base_elements(input_paths, output_path, audio_format \\ :s16le) do
    stream_format = %RawAudio{
      channels: 1,
      sample_rate: 16_000,
      sample_format: audio_format
    }

    input_paths
    |> Enum.with_index(1)
    |> Enum.map(fn {path, index} ->
      [
        child({:parser, index}, %Membrane.AudioMixer.Support.RawAudioParser{
          stream_format: stream_format
        }),
        child({:file_src, index}, %Membrane.File.Source{location: path})
      ]
    end)
    |> Enum.concat([child(:file_sink, %Membrane.File.Sink{location: output_path})])
  end

  defp get_live_mixers() do
    mixer = %Membrane.LiveAudioMixer{prevent_clipping: false}
    preventer_mixer = %Membrane.LiveAudioMixer{mixer | prevent_clipping: true}
    native_mixer = %Membrane.LiveAudioMixer{preventer_mixer | native_mixer: true}

    {[child(:mixer, mixer)], [child(:mixer, preventer_mixer)], [child(:mixer, native_mixer)]}
  end

  defp get_offline_mixers() do
    mixer = %Membrane.AudioMixer{prevent_clipping: false}
    preventer_mixer = %Membrane.AudioMixer{mixer | prevent_clipping: true}
    native_mixer = %Membrane.AudioMixer{preventer_mixer | native_mixer: true}

    {[child(:mixer, mixer)], [child(:mixer, preventer_mixer)], [child(:mixer, native_mixer)]}
  end

  defp perform_test(
         {clipper_elements, preventer_elements, native_elements},
         links,
         clipper_reference,
         preventer_reference,
         output_path,
         live_mixer? \\ false
       ) do
    do_perform_test(clipper_elements ++ links, clipper_reference, output_path, live_mixer?)
    do_perform_test(preventer_elements ++ links, preventer_reference, output_path, live_mixer?)
    do_perform_test(native_elements ++ links, preventer_reference, output_path, live_mixer?)
  end

  defp do_perform_test(structure, reference_path, output_path, false) do
    assert pipeline = Pipeline.start_link_supervised!(spec: structure)
    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    assert {:ok, reference_file} = File.read(reference_path)
    assert {:ok, output_file} = File.read(output_path)
    assert reference_file == output_file
  end

  defp do_perform_test(structure, reference_path, output_path, true) do
    assert pipeline = Pipeline.start_link_supervised!(spec: structure)

    Pipeline.message_child(pipeline, :mixer, :schedule_eos)

    assert_end_of_stream(pipeline, :file_sink, :input, 20_000)

    assert {:ok, reference_file} = File.read(reference_path)
    assert {:ok, output_file} = File.read(output_path)

    # Live audio mixer produces audio chunks in intervals.
    # Each tick produces the same amount of audio.
    # So before eof stream live mixer can produce additional silence.
    assert <<^reference_file::binary-size(byte_size(reference_file)), _rest::binary>> =
             output_file
  end
end
