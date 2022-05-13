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
  """

  use Membrane.Bin
  use Bunch

  require Membrane.Logger

  alias Membrane.{AudioMixer, ParentSpec, RawAudio}
  alias Membrane.Bin.PadData
  alias Membrane.Caps.Matcher

  @supported_caps [
    {RawAudio,
     sample_format: Matcher.one_of([:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be])},
    Membrane.RemoteStream
  ]

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
              ]

  def_input_pad :input,
    mode: :pull,
    availability: :on_request,
    demand_unit: :bytes,
    caps: @supported_caps,
    options: [
      offset: [
        spec: Time.t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  def_output_pad :output,
    mode: :pull,
    demand_unit: :bytes,
    availability: :always,
    caps: RawAudio

  @impl true
  def handle_init(options) do
    state = options |> Map.from_struct()

    {:ok, state}
  end

  @impl true
  def handle_pad_added(_pad_ref, %{playback_state: :stopped}, state) do
    {:ok, state}
  end

  def handle_pad_added(_pad_ref, %{playback_state: playback_state}, _state)
      when playback_state != :stopped do
    raise("""
    All pads should be added before starting the #{__MODULE__}.
    Pad added event received in playback state #{playback_state}.
    """)
  end

  @impl true
  def handle_other(:linking_finished, ctx, state) do
    input_pads =
      ctx.pads
      |> Map.values()
      |> Enum.filter(fn %{direction: direction} -> direction == :input end)

    spec = gen_mixing_spec(input_pads, state.max_inputs_per_node, state.mixer_options)
    {{:ok, spec: spec}, state}
  end

  @spec gen_mixing_spec([PadData.t()], pos_integer(), AudioMixer.t()) ::
          ParentSpec.t()
  def gen_mixing_spec([single_input_data], _max_degree, mixer_options) do
    children = [{:mixer, mixer_options}]
    offset = single_input_data.options.offset

    links = [
      link_bin_input(single_input_data.ref)
      |> via_in(:input, options: [offset: offset])
      |> to(:mixer)
      |> to_bin_output()
    ]

    %ParentSpec{links: links, children: children}
  end

  def gen_mixing_spec(inputs_data, max_degree, mixer_options) do
    inputs_number = length(inputs_data)
    levels = ceil(:math.log(inputs_number) / :math.log(max_degree))

    consts = %{
      max_degree: max_degree,
      levels: levels,
      mixer_options: mixer_options
    }

    # levels will be 0-indexed with tree root being level 0
    leaves_level = levels - 1

    # links generator to be used only for botttom level of mixing tree
    links_generator = fn _inputs_number, nodes_num, level ->
      # inputs_number == length(inputs_data)
      inputs_data
      |> Enum.with_index()
      |> Enum.map(fn {%{ref: pad_ref, options: %{offset: offset}}, i} ->
        target_node_idx = rem(i, nodes_num)

        link_bin_input(pad_ref)
        |> via_in(:input, options: [offset: offset])
        |> to("mixer_#{level}_#{target_node_idx}")
      end)
    end

    build_mixers_tree(leaves_level, inputs_number, [], [], consts, links_generator)
  end

  defp mid_tree_link_generator(inputs_number, level_nodes_num, level) do
    0..(inputs_number - 1)//1
    |> Enum.map(fn input_index ->
      current_level_node_idx = rem(input_index, level_nodes_num)

      link("mixer_#{level + 1}_#{input_index}")
      |> to("mixer_#{level}_#{current_level_node_idx}")
    end)
  end

  defp build_mixers_tree(
         level_index,
         inputs_number,
         elem_acc,
         link_acc,
         consts,
         link_generator \\ &mid_tree_link_generator/3
       )

  defp build_mixers_tree(level, 1, children, link_acc, _consts, _link_generator)
       when level < 0 do
    links = [link("mixer_0_0") |> to_bin_output()] ++ link_acc
    %ParentSpec{children: children, links: links}
  end

  defp build_mixers_tree(level, inputs_number, elem_acc, link_acc, consts, link_generator) do
    nodes_num = ceil(inputs_number / consts.max_degree)

    children =
      0..(nodes_num - 1)//1
      |> Enum.map(fn i ->
        {"mixer_#{level}_#{i}", consts.mixer_options}
      end)

    links = link_generator.(inputs_number, nodes_num, level)

    build_mixers_tree(
      level - 1,
      nodes_num,
      children ++ elem_acc,
      links ++ link_acc,
      consts
    )
  end
end
