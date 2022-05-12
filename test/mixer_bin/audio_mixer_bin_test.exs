defmodule Membrane.AudioMixerBinTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Membrane.ParentSpec
  import Membrane.Testing.Assertions

  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline
  alias Membrane.ParentSpec

  @input_path_1 Path.expand("../fixtures/mixer_bin/input-1.raw", __DIR__)
  @input_path_2 Path.expand("../fixtures/mixer_bin/input-2.raw", __DIR__)

  defmodule BinTestPipeline do
    use Membrane.Pipeline
    @impl true
    def handle_init(%{spec: spec, bin_name: name}) do
      send(self(), {:linking_finished, name})
      {{:ok, spec: spec, playback: :playing}, %{}}
    end

    @impl true
    def handle_other({:linking_finished, name}, _ctx, state) do
      {{:ok, forward: {name, :linking_finished}}, state}
    end
  end

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
      caps = %RawAudio{
        channels: 1,
        sample_rate: 16_000,
        sample_format: audio_format
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

      mixer_bin_pipeline = %Pipeline.Options{
        module: BinTestPipeline,
        custom_args: %{spec: %ParentSpec{children: elements_bin, links: links}, bin_name: :mixer}
      }

      {mixer_pipeline, mixer_bin_pipeline}
    end

    defp play_pipeline(pipeline_options) do
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)
      assert_start_of_stream(pid, :file_sink, :input)
      assert_end_of_stream(pid, :file_sink, :input)
      Pipeline.terminate(pid, blocking?: true)
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
