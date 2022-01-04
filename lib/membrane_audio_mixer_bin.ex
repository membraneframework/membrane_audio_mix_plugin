defmodule Membrane.AudioMixerBin do
  @moduledoc """
  Bin element distributing a mixing job between multiple `Membrane.AudioMixer` elements.

  A tree of AudioMixers is created according to `max_node_degree` parameter:
  - if number of input tracks is smaller than `max_node_degree`, only one AudioMixer element is created for the entire job
  - if there are more input tracks than `max_node_degree`, there are created enough mixers so that each mixer has at most
  `max_node_degree` inputs - outputs from those mixers are then mixed again following the same rules -
  another level of mixers is created having enough mixers so that each mixer on this level has at most
  `max_node_degree` inputs (those are now the outputs of the previous level mixers).
  Levels are created until only one mixer in the level is needed - output from this mixer is the final mixed track.

  Bin allows for specyfiyng options for `Membrane.AudioMixer`, which are applied for all AudioMixers.

  Recommended to use in case of mixing jobs with many inputs.
  """

  use Membrane.Bin
  use Bunch

  alias Membrane.{Pad, ParentSpec, AudioMixer}
  alias Membrane.Caps.Audio.Raw

  require Membrane.Logger

  alias Membrane.Caps.Matcher

  @supported_caps {Raw,
                   format: Matcher.one_of([:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be])}

  def_options max_node_degree: [
                type: :int,
                description: """
                Maximum number of inputs to a single mixer in the mixres tree. Must be at least 2.
                """,
                default: 10
              ],
              inputs: [
                type: :int,
                description: """
                Number of all input files to be mixed.
                """
              ],
              caps: [
                type: :struct,
                spec: Raw.t(),
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                """,
                default: nil
              ],
              frames_per_buffer: [
                type: :integer,
                spec: pos_integer(),
                description: """
                Assumed number of raw audio frames in each buffer.
                Used when converting demand from buffers into bytes.
                """,
                default: 2048
              ],
              prevent_clipping: [
                type: :boolean,
                spec: boolean(),
                description: """
                Defines how the mixer should act in the case when an overflow happens.
                - If true, the wave will be scaled down, so a peak will become the maximal
                value of the sample in the format. See `Membrane.AudioMixer.ClipPreventingAdder`.
                - If false, overflow will be clipped to the maximal value of the sample in
                the format. See `Membrane.AudioMixer.Adder`.
                """,
                default: true
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
    caps: Raw

  @impl true
  def handle_init(options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:added_pad_count, 0)

    {children, links} = create_mixers_tree(state)
    spec = %ParentSpec{children: children, links: links}

    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_pad_added(
        _pad_ref,
        _ctx,
        %{added_pad_count: added_pad_count, inputs: inputs}
      )
      when added_pad_count >= inputs do
    raise("provided more input pads than specified via `inputs` option (#{inputs})")
  end

  def handle_pad_added(
        pad_ref,
        ctx,
        %{added_pad_count: added_pad_count, max_node_degree: max_node_degree} = state
      ) do
    %Pad.Data{options: %{offset: offset}} = ctx.pads[pad_ref]
    mixer_idx = div(added_pad_count, max_node_degree)

    link =
      link_bin_input(pad_ref)
      |> via_in(:input, options: [offset: offset])
      |> to("mixer_0_#{mixer_idx}")

    {{:ok, spec: %ParentSpec{links: [link]}}, %{state | added_pad_count: added_pad_count + 1}}
  end

  @impl true
  def handle_stopped_to_prepared(
        _context,
        %{inputs: inputs, added_pad_count: inputs} = state
      ) do
    {:ok, state}
  end

  def handle_stopped_to_prepared(
        _context,
        %{inputs: inputs, added_pad_count: added_pad_count}
      )
      when inputs != added_pad_count do
    raise(
      "provided #{added_pad_count} input pads but #{inputs} where specified via `inputs` option"
    )
  end

  # create all mixers and links between them - `levels` of the mixers' tree are labeled starting from 0 and counted
  # from the leaves to the root, where one final mixer (root) has the highest level.
  defp create_mixers_tree(state, level \\ 0, acc \\ {[], []}, prev_inputs_count \\ nil)

  defp create_mixers_tree(state, 0, _acc, _prev_inputs_count) do
    n_mixers = ceil(state.inputs / state.max_node_degree)

    children =
      0..(n_mixers - 1)
      |> Enum.map(fn i ->
        {"mixer_#{0}_#{i}",
         %AudioMixer{
           caps: state.caps,
           frames_per_buffer: state.frames_per_buffer,
           prevent_clipping: state.prevent_clipping
         }}
      end)

    create_mixers_tree(state, 1, {children, []}, n_mixers)
  end

  # end case - link one final mixer to bin output
  defp create_mixers_tree(_state, level, {children, links}, 1) do
    last_mixer_name = "mixer_#{level - 1}_#{0}"
    links = [link(last_mixer_name) |> to_bin_output()] ++ links
    {children, links}
  end

  defp create_mixers_tree(state, level, {children, links}, prev_inputs_count) do
    n_mixers = ceil(prev_inputs_count / state.max_node_degree)

    # create current level of mixers
    new_children =
      0..(n_mixers - 1)
      |> Enum.map(fn i ->
        {"mixer_#{level}_#{i}",
         %AudioMixer{
           caps: state.caps,
           frames_per_buffer: state.frames_per_buffer,
           prevent_clipping: state.prevent_clipping
         }}
      end)

    # link current mixers with mixers from previous level
    new_links =
      0..(prev_inputs_count - 1)
      |> Enum.flat_map(fn i ->
        parent = div(i, state.max_node_degree)

        [
          link("mixer_#{level - 1}_#{i}")
          |> to("mixer_#{level}_#{parent}")
        ]
      end)

    create_mixers_tree(
      state,
      level + 1,
      {children ++ new_children, links ++ new_links},
      n_mixers
    )
  end
end
