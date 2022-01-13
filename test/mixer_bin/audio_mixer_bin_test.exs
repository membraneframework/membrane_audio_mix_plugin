defmodule Membrane.AudioMixerBinTest do
  @moduledoc false

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.Caps.Audio.Raw
  alias Membrane.Testing.Pipeline

  @input_path_1 Path.expand("../fixtures/mixer_bin/input-1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/mixer_bin/input-2.raw", __DIR__)

  defp expand_path(file_name) do
    Path.expand("../fixtures/mixer_bin/#{file_name}", __DIR__)
  end

  describe "AudioMixerBin should mix tracks the same as AudioMixer when" do
    defp prepare_outputs() do
      output_path_mixer = expand_path("output1.raw")
      output_path_bin = expand_path("output2.raw")

      File.rm(output_path_mixer)
      File.rm(output_path_bin)

      on_exit(fn ->
        File.rm(output_path_mixer)
        File.rm(output_path_bin)
      end)

      {output_path_mixer, output_path_bin}
    end

    defp create_pipelines(
           input_paths,
           output_path_mixer,
           output_path_bin,
           max_inputs_per_node,
           audio_format \\ :s16le
         ) do
      caps = %Raw{
        channels: 1,
        sample_rate: 16_000,
        format: audio_format
      }

      elements =
        input_paths
        |> Enum.with_index(1)
        |> Enum.map(fn {path, index} ->
          {"file_src_#{index}", %Membrane.File.Source{location: path}}
        end)

      elements_mixer =
        elements ++
          [
            mixer: %Membrane.AudioMixer{
              caps: caps,
              prevent_clipping: false
            },
            file_sink: %Membrane.File.Sink{location: output_path_mixer}
          ]

      elements_bin =
        elements ++
          [
            mixer: %Membrane.AudioMixerBin{
              max_inputs_per_node: max_inputs_per_node,
              mixer_options: %Membrane.AudioMixer{
                caps: caps,
                prevent_clipping: false
              }
            },
            file_sink: %Membrane.File.Sink{location: output_path_bin}
          ]

      links =
        1..length(input_paths)
        |> Enum.flat_map(fn index ->
          [link("file_src_#{index}") |> to(:mixer)]
        end)

      links = links ++ [link(:mixer) |> to(:file_sink)]

      mixer_pipeline = %Pipeline.Options{elements: elements_mixer, links: links}
      mixer_bin_pipeline = %Pipeline.Options{elements: elements_bin, links: links}

      {mixer_pipeline, mixer_bin_pipeline}
    end

    defp play_pipeline(pipeline_options) do
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)
      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :file_sink, :input, 5_000)
      Pipeline.stop_and_terminate(pid, blocking?: true)
    end

    test "only one AudioMixer is used by AudioMixerBin" do
      {output_path_mixer, output_path_bin} = prepare_outputs()

      {a, b} =
        create_pipelines(
          [@input_path_1],
          output_path_mixer,
          output_path_bin,
          3
        )

      play_pipeline(a)
      play_pipeline(b)

      assert {:ok, output_1} = File.read(output_path_mixer)
      assert {:ok, output_2} = File.read(output_path_bin)
      assert output_1 == output_2
    end

    test "multiple AudioMixers are used by AudioMixerBin" do
      {output_path_mixer, output_path_bin} = prepare_outputs()

      {a, b} =
        create_pipelines(
          [@input_path_1, @input_path_1, @input_path_2],
          output_path_mixer,
          output_path_bin,
          2
        )

      play_pipeline(a)
      play_pipeline(b)

      assert {:ok, output_1} = File.read(output_path_mixer)
      assert {:ok, output_2} = File.read(output_path_bin)
      assert output_1 == output_2
    end
  end
end
