defmodule MixerTest do
  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Testing.Pipeline

  @input_path_1 Path.expand("../fixtures/input-1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/input-2.raw", __DIR__)

  defp expand_path(file_name) do
    Path.expand("../fixtures/#{file_name}", __DIR__)
  end

  defp prepare_output() do
    output_path = expand_path("output.raw")

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  defp create_elements(input_paths, output_path, audio_format \\ :s16le) do
    input_paths
    |> Enum.with_index(1)
    |> Enum.map(fn {path, index} ->
      {String.to_atom("file_src_#{index}"), %Membrane.File.Source{location: path}}
    end)
    |> Enum.concat(
      mixer: %Membrane.AudioMixer{
        caps: %Caps{
          channels: 1,
          sample_rate: 16_000,
          format: audio_format
        }
      },
      file_sink: %Membrane.File.Sink{location: output_path}
    )
  end

  defp perform_test(elements, links, reference_path, output_path) do
    pipeline_options = %Pipeline.Options{elements: elements, links: links}
    assert {:ok, pid} = Pipeline.start_link(pipeline_options)

    assert Pipeline.play(pid) == :ok
    assert_end_of_stream(pid, :file_sink, :input, 5_000)
    Pipeline.stop_and_terminate(pid, blocking?: true)

    assert {:ok, reference_file} = File.read(reference_path)
    assert {:ok, output_file} = File.read(output_path)
    assert reference_file == output_file
  end

  describe "Audio Mixer should mix" do
    test "two tracks with the same size" do
      output_path = prepare_output()
      reference_path = expand_path("reference-same-size.raw")

      elements = create_elements([@input_path_1, @input_path_1], output_path)

      links = [
        link(:file_src_1)
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "two tracks with different sizes" do
      output_path = prepare_output()
      reference_path = expand_path("reference-different-size.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "tracks when the shorter one has an offset" do
      output_path = prepare_output()
      reference_path = expand_path("reference-offset-first.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(125)])
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "tracks when the longer one has an offset" do
      output_path = prepare_output()
      reference_path = expand_path("reference-offset-second.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(250)])
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    @tag :focus
    test "tracks when both have offsets" do
      output_path = prepare_output()
      reference_path = expand_path("reference-offsets-both.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(500)])
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(125)])
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "three tracks" do
      output_path = prepare_output()
      reference_path = expand_path("reference-three.raw")

      elements = create_elements([@input_path_1, @input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(250)])
        |> to(:mixer),
        link(:file_src_3)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(125)])
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "tracks in unsinged format" do
      output_path = prepare_output()
      reference_path = expand_path("reference-unsigned.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path, :u16le)

      links = [
        link(:file_src_1)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(125)])
        |> to(:mixer)
        |> to(:file_sink),
        link(:file_src_2)
        |> via_in(:input, options: [offset: Membrane.Time.microseconds(125)])
        |> to(:mixer)
      ]

      perform_test(elements, links, reference_path, output_path)
    end
  end
end
