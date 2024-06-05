defmodule Membrane.AudioMixerBinTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @input_path_1 Path.expand("../fixtures/mixer_bin/input-1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/mixer_bin/input-2.raw", __DIR__)

  @moduletag :tmp_dir
  describe "AudioMixerBin should mix tracks the same as AudioMixer when" do
    defp prepare_outputs(%{tmp_dir: out_dir}) do
      output_path_mixer = Path.join(out_dir, "output1.raw")
      output_path_bin = Path.join(out_dir, "output2.raw")

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
      stream_format = %RawAudio{
        channels: 1,
        sample_rate: 16_000,
        sample_format: audio_format
      }

      spec_file_src =
        input_paths
        |> Enum.with_index(1)
        |> Enum.map(fn {path, index} ->
          child({:file_src, index}, %Membrane.File.Source{location: path}) |> get_child(:mixer)
        end)

      spec_mixer =
        spec_file_src ++
          [
            child(:mixer, %Membrane.AudioMixer{
              stream_format: stream_format,
              prevent_clipping: false
            })
            |> child(:file_sink, %Membrane.File.Sink{location: output_path_mixer})
          ]

      spec_bin =
        spec_file_src ++
          [
            child(:mixer, %Membrane.AudioMixerBin{
              max_inputs_per_node: max_inputs_per_node,
              number_of_inputs: length(input_paths),
              mixer_options: %Membrane.AudioMixer{
                stream_format: stream_format,
                prevent_clipping: false
              }
            })
            |> child(:file_sink, %Membrane.File.Sink{location: output_path_bin})
          ]

      mixer_pipeline = [
        spec: spec_mixer
      ]

      mixer_bin_pipeline = [
        spec: spec_bin
      ]

      {
        mixer_pipeline,
        mixer_bin_pipeline
      }
    end

    defp play_pipeline(pipeline_options) do
      assert pipeline = Pipeline.start_link_supervised!(pipeline_options)

      assert_start_of_stream(pipeline, :file_sink, :input)
      assert_end_of_stream(pipeline, :file_sink, :input)

      Pipeline.terminate(pipeline)
    end

    test "there's only one input", ctx do
      {output_path_mixer, output_path_bin} = prepare_outputs(ctx)

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

    test "only one AudioMixer is used by AudioMixerBin", ctx do
      {output_path_mixer, output_path_bin} = prepare_outputs(ctx)

      {a, b} =
        create_pipelines(
          [@input_path_1, @input_path_2],
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

    test "multiple AudioMixers are used by AudioMixerBin", ctx do
      {output_path_mixer, output_path_bin} = prepare_outputs(ctx)

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
