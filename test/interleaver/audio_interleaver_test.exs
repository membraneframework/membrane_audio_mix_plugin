defmodule Membrane.AudioInterleaverTest do
  @moduledoc """
  Tests for AudioInterleaver module.
  """

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  require Membrane.Logger

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @in1 Path.expand("../fixtures/interleaver/in1.raw", __DIR__)
  @in2 Path.expand("../fixtures/interleaver/in2.raw", __DIR__)
  @in3 Path.expand("../fixtures/interleaver/in3.raw", __DIR__)
  @in1b Path.expand("../fixtures/interleaver/in1b.raw", __DIR__)

  defp expand_path(file_name) do
    Path.expand("../fixtures/interleaver/#{file_name}", __DIR__)
  end

  defp prepare_output() do
    output_path = expand_path("output.raw")

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  describe "Audio Interleaver should interleave" do
    defp create_elements(input_paths, output_path, order, audio_format \\ :s16le) do
      input_paths
      |> Enum.with_index(1)
      |> Enum.map(fn {path, index} ->
        {String.to_atom("file_src_#{index}"), %Membrane.File.Source{location: path}}
      end)
      |> Enum.concat(
        interleaver: %Membrane.AudioInterleaver{
          input_caps: %RawAudio{
            channels: 1,
            sample_rate: 16_000,
            sample_format: audio_format
          },
          order: order
        },
        file_sink: %Membrane.File.Sink{location: output_path}
      )
    end

    defp perform_test(children, links, reference_path, output_path) do
      pipeline_options = [children: children, links: links]
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)

      assert_end_of_stream(pid, :file_sink, :input, 5_000)
      Pipeline.terminate(pid, blocking?: true)

      assert {:ok, reference_file} = File.read(reference_path)
      assert {:ok, output_file} = File.read(output_path)
      assert reference_file == output_file
    end

    test "two tracks with the same size" do
      output_path = prepare_output()
      reference_path = expand_path("out_1_2_s16le.raw")
      elements = create_elements([@in1, @in2], output_path, [1, 2])

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1))
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "two tracks with custom order" do
      output_path = prepare_output()
      reference_path = expand_path("out_1_2_s16le.raw")
      elements = create_elements([@in2, @in1], output_path, [2, 1])

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1))
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "two tracks with atoms as names" do
      output_path = prepare_output()
      reference_path = expand_path("out_1_2_s16le.raw")
      elements = create_elements([@in2, @in1], output_path, [:two, :one])

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, :one))
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, :two))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      perform_test(elements, links, reference_path, output_path)
    end

    test "two tracks with different size (appending shorter input) " do
      output_path = prepare_output()

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1))
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      elements = create_elements([@in1b, @in2], output_path, [1, 2])
      perform_test(elements, links, expand_path("out_1b_2_s16le.raw"), output_path)

      elements = create_elements([@in1b, @in2], output_path, [1, 2], :s8)
      perform_test(elements, links, expand_path("out_1b_2_s8.raw"), output_path)
    end

    test "tracks with offset" do
      output_path = prepare_output()

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1), options: [offset: Membrane.Time.microseconds(125)])
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      elements = create_elements([@in1, @in2], output_path, [1, 2])
      perform_test(elements, links, expand_path("out_1_2_s16le_offset125.raw"), output_path)

      elements = create_elements([@in1, @in2], output_path, [1, 2], :s8)
      perform_test(elements, links, expand_path("out_1_2_s8_offset125.raw"), output_path)
    end

    test "3 tracks, varying size" do
      output_path = prepare_output()
      reference_path = expand_path("out_1b_2_3_s16le.raw")

      elements = create_elements([@in1b, @in2, @in3], output_path, [1, 2, 3])

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1))
        |> to(:interleaver),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:interleaver),
        link(:file_src_3)
        |> via_in(Pad.ref(:input, 3))
        |> to(:interleaver)
        |> to(:file_sink)
      ]

      perform_test(elements, links, reference_path, output_path)
    end
  end
end
