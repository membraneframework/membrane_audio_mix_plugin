defmodule Membrane.AudioMixerBin do
  @moduledoc """
  Bin element distributing a mixing job between multiple `Membrane.AudioMixer` elements.

  A tree of AudioMixers is created according to `max_inputs_per_node` parameter:
  - if number of input tracks is smaller than `max_inputs_per_node`, only one AudioMixer element is created for the entire job
  - if there are more input tracks than `max_inputs_per_node`, there are created enough mixers so that each mixer has at most
  `max_inputs_per_node` inputs - outputs from those mixers are then mixed again following the same rules -
  another level of mixers is created having enough mixers so that each mixer on this level has at most
  `max_inputs_per_node` inputs (those are now the outputs of the previous level mixers).
  Levels are created until only one mixer in the level is needed - output from this mixer is the final mixed track.

  Bin allows for specifying options for `Membrane.AudioMixer`, which are applied for all AudioMixers.

  Recommended to use in case of mixing jobs with many inputs.

  A number of inputs to the bin must be specified in the `number_of_inputs` option.
  """

  use Membrane.Bin
  use Bunch

  require Membrane.Logger

  alias Membrane.{AudioMixer, RawAudio}
  alias Membrane.Bin.PadData

  def_options max_inputs_per_node: [
                spec: pos_integer(),
                description: """
                The maximum number of inputs to a single mixer in the mixers tree. Must be at least 2.
                """,
                default: 10
              ],
              mixer_options: [
                spec: AudioMixer.t(),
                description: """
                The options that would be passed to each created AudioMixer.
                """,
                default: %AudioMixer{}
              ],
              number_of_inputs: [
                spec: pos_integer(),
                description: """
                The exact number of inputs to the bin. Must be at least 1.
                """
              ]

  def_input_pad :input,
    availability: :on_request,
    accepted_format:
      any_of(
        %RawAudio{sample_format: sample_format}
        when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be],
        Membrane.RemoteStream
      ),
    options: [
      offset: [
        spec: Time.t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  def_output_pad :output, accepted_format: RawAudio

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.put(:current_inputs, 0)
      |> Map.from_struct()

    {[], state}
  end

  @impl true
  def handle_pad_added({_mod, :input, _ref} = _pad_ref, %{playback: :stopped} = ctx, state) do
    current_inputs = state.current_inputs + 1

    if current_inputs > state.number_of_inputs do
      raise """
      The number of inputs to the #{__MODULE__} has exceeded the maximum number of inputs per node (#{current_inputs} > #{state.number_of_inputs}).
      """
    end

    state = %{state | current_inputs: current_inputs}

    if current_inputs == state.number_of_inputs do
      spec = create_spec(ctx.pads, state.max_inputs_per_node, state.mixer_options)

      {[spec: spec], state}
    else
      {[], state}
    end
  end

  def handle_pad_added(_pad_ref, %{playback: playback}, _state)
      when playback != :stopped do
    raise """
    All pads should be added before starting the #{__MODULE__}.
    Pad added event received in playback state #{playback}.
    """
  end

  @impl true
  def handle_parent_notification({:number_of_inputs, number_of_inputs}, _ctx, state) do
    if state.current_inputs > number_of_inputs do
      raise """
      The current number of inputs to the #{__MODULE__} exceeds new number of inputs (#{state.current_inputs} > #{number_of_inputs}).
      """
    end

    state = %{state | number_of_inputs: number_of_inputs}

    {[], state}
  end

  defp create_spec(pads, max_inputs_per_node, mixer_options) do
    input_pads =
      pads
      |> Map.values()
      |> Enum.filter(fn %{direction: direction} -> direction == :input end)

    spec = gen_mixing_spec(input_pads, max_inputs_per_node, mixer_options)
    spec
  end

  @doc """
  Generates a spec for a single mixer or a tree of mixers.

  Levels of the tree will be 0-indexed with tree root being level 0
  For a bottom level of mixing tree (leaves of the tree) links generator will be used to generate links between inputs and mixers.
  """
  @spec gen_mixing_spec([PadData.t()], pos_integer(), AudioMixer.t()) ::
          Membrane.ChildrenSpec.t()
  def gen_mixing_spec([single_input_data], _max_degree, mixer_options) do
    offset = single_input_data.options.offset

    bin_input(single_input_data.ref)
    |> via_in(:input, options: [offset: offset])
    |> child(:mixer, mixer_options)
    |> bin_output()
  end

  def gen_mixing_spec(inputs_data, max_degree, mixer_options) do
    inputs_number = length(inputs_data)
    levels = ceil(:math.log(inputs_number) / :math.log(max_degree))

    consts = %{
      max_degree: max_degree,
      levels: levels,
      mixer_options: mixer_options
    }

    leaves_level = levels - 1

    links_generator = fn _inputs_number, nodes_num, level ->
      inputs_data
      |> Enum.with_index()
      |> Enum.map(fn {%{ref: pad_ref, options: %{offset: offset}}, i} ->
        target_node_idx = rem(i, nodes_num)

        bin_input(pad_ref)
        |> via_in(:input, options: [offset: offset])
        |> get_child({:mixer, {level, target_node_idx}})
      end)
    end

    build_mixers_tree(leaves_level, inputs_number, [], consts, links_generator)
  end

  defp mid_tree_link_generator(inputs_number, level_nodes_num, level) do
    0..(inputs_number - 1)//1
    |> Enum.map(fn input_index ->
      current_level_node_idx = rem(input_index, level_nodes_num)

      get_child({:mixer, {level + 1, input_index}})
      |> get_child({:mixer, {level, current_level_node_idx}})
    end)
  end

  defp build_mixers_tree(
         level_index,
         inputs_number,
         spec_acc,
         consts,
         link_generator \\ &mid_tree_link_generator/3
       )

  defp build_mixers_tree(level, 1, spec_acc, _consts, _link_generator)
       when level < 0 do
    [get_child({:mixer, {0, 0}}) |> bin_output()] ++ spec_acc
  end

  defp build_mixers_tree(level, inputs_number, spec_acc, consts, link_generator) do
    nodes_num = ceil(inputs_number / consts.max_degree)

    children =
      0..(nodes_num - 1)//1
      |> Enum.map(fn i ->
        child({:mixer, {level, i}}, consts.mixer_options)
      end)

    links = link_generator.(inputs_number, nodes_num, level)

    build_mixers_tree(
      level - 1,
      nodes_num,
      spec_acc ++ children ++ links,
      consts
    )
  end
end
