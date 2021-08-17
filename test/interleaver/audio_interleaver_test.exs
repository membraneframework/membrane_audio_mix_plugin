defmodule Membrane.AudioInterleaverTest do
  @moduledoc """
  Tests for DoMix module. It contatins only one public function - `mix(buffers, caps)`, so tests
  check output of the mixing for serveral formats.

  Debugging: before every test, Membrane.Logger prints message with used caps. They can be seen
  only when particular test do not pass. In such case last debug message contains caps for
  which the test did not pass.
  """

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.AudioInterleaver
  alias Membrane.AudioMixer.DoInterleave
  alias Membrane.Testing.Pipeline
  alias Membrane.Caps.Audio.Raw, as: Caps

  require Membrane.Logger

  @input_path_1 Path.expand("../fixtures/interleaver/in1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/interleaver/in2.raw", __DIR__)

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
    defp create_elements(input_paths, output_path, audio_format \\ :s16le) do
      input_paths
      |> Enum.with_index(1)
      |> Enum.map(fn {path, index} ->
        {String.to_atom("file_src_#{index}"), %Membrane.File.Source{location: path}}
      end)
      |> Enum.concat(
        mixer: %Membrane.AudioInterleaver{
          caps: %Caps{
            channels: 1,
            sample_rate: 16_000,
            format: audio_format
          },
          order: [1, 2]
        },
        file_sink: %Membrane.File.Sink{location: output_path}
      )
    end

    defp perform_test(elements, links, reference_path, output_path) do
      pipeline_options = %Pipeline.Options{elements: elements, links: links}
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)

      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :file_sink, :input, 6_000)
      Pipeline.stop_and_terminate(pid, blocking?: true)

      assert {:ok, reference_file} = File.read(reference_path)
      assert {:ok, output_file} = File.read(output_path)
      assert reference_file == output_file
    end

    test "two tracks with the same size" do
      output_path = prepare_output()
      reference_path = expand_path("out12_size2.raw")

      elements = create_elements([@input_path_1, @input_path_2], output_path)

      links = [
        link(:file_src_1)
        |> via_in(Pad.ref(:input, 1))
        |> to(:mixer),
        link(:file_src_2)
        |> via_in(Pad.ref(:input, 2))
        |> to(:mixer)
        |> to(:file_sink)
      ]

      perform_test(elements, links, reference_path, output_path)
    end
  end
end
