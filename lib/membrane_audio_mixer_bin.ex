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

  Bin allows for specyfiyng options for `Membrane.AudioMixer`, which are applied for all AudioMixers.

  Recommended to use in case of mixing jobs with many inputs.
  """

  use Membrane.Bin
  use Bunch

  require Membrane.Logger

  alias __MODULE__.MixerOptions
  alias Membrane.{Pad, ParentSpec, AudioMixer}
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Caps.Matcher

  @supported_caps {Raw,
                   format: Matcher.one_of([:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be])}

  def_options max_inputs_per_node: [
                type: :int,
                description: """
                The maximum number of inputs to a single mixer in the mixers tree. Must be at least 2.
                """,
                default: 10
              ],
              mixer_options: [
                type: :any,
                spec: MixerOptions.t(),
                description: """
                The options that would be passed to each created AudioMixer.
                """,
                default: nil
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

  defmodule MixerOptions do
    @moduledoc """
    Structure representing options that would be passed to each created Membrane.AudioMixer element.
    """
    defstruct caps: nil, frames_per_buffer: 2048, prevent_clipping: true

    @type t :: %__MODULE__{
            caps: Raw.t(),
            frames_per_buffer: pos_integer(),
            prevent_clipping: boolean()
          }
  end

  @impl true
  def handle_init(options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:inputs, 0)
      |> Map.update!(:mixer_options, fn val ->
        if val == nil, do: %MixerOptions{}, else: val
      end)

    {{:ok, spec: %ParentSpec{}}, state}
  end

  @impl true
  def handle_pad_added(pad_ref, %{playback_state: :stopped} = ctx, %{inputs: inputs} = state) do
    %Pad.Data{options: %{offset: offset}} = ctx.pads[pad_ref]
    {children, links} = link_new_input(pad_ref, offset, state)

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{state | inputs: inputs + 1}}
  end

  def handle_pad_added(_pad_ref, %{playback_state: playback_state}, _state)
      when playback_state != :stopped do
    raise("All pads should be added before starting the #{__MODULE__}. \
Pad added event received in playback state.")
  end

  @impl true
  def handle_stopped_to_prepared(_context, state) do
    {children, links} = create_mixers_tree(state)

    {{:ok, spec: %ParentSpec{children: children, links: links}}, state}
  end

  # Link new input to correct mixer. Creates mixer if doesn't exist.
  defp link_new_input(pad_ref, offset, state) do
    mixer_idx = div(state.inputs, state.max_inputs_per_node)
    create_new_mixer = rem(state.inputs, state.max_inputs_per_node) == 0

    children =
      if create_new_mixer do
        [{"mixer_0_#{mixer_idx}", create_audio_mixer(state.mixer_options)}]
      else
        []
      end

    link =
      link_bin_input(pad_ref)
      |> via_in(:input, options: [offset: offset])
      |> to("mixer_0_#{mixer_idx}")

    {children, [link]}
  end

  # Create mixers and links between them. `levels` of the mixers' tree are labeled starting from 0
  # and counted from the leaves to the root, where one final mixer (root) has the highest level.
  # Level 0 mixers where created during adding input pads, so only mixers starting from level 1 are created now.
  defp create_mixers_tree(state, level \\ 1, acc \\ {[], []}, current_level_inputs \\ nil)

  defp create_mixers_tree(state, 1, {[], []}, nil) do
    first_level_mixers = ceil(state.inputs / state.max_inputs_per_node)
    create_mixers_tree(state, 1, {[], []}, first_level_mixers)
  end

  # end case - link one final mixer to bin output
  defp create_mixers_tree(_state, level, {children, links}, 1) do
    last_mixer_name = "mixer_#{level - 1}_#{0}"
    links = [link(last_mixer_name) |> to_bin_output() | links]

    {List.flatten(children), List.flatten(links)}
  end

  defp create_mixers_tree(state, level, {children, links}, current_level_inputs) do
    n_mixers = ceil(current_level_inputs / state.max_inputs_per_node)
    # create current level of mixers
    new_children =
      0..(n_mixers - 1)
      |> Enum.map(fn i ->
        {"mixer_#{level}_#{i}", create_audio_mixer(state.mixer_options)}
      end)

    # link current mixers with mixers from previous level
    new_links =
      0..(current_level_inputs - 1)
      |> Enum.map(fn i ->
        parent = div(i, state.max_inputs_per_node)

        link("mixer_#{level - 1}_#{i}")
        |> to("mixer_#{level}_#{parent}")
      end)

    create_mixers_tree(
      state,
      level + 1,
      {[new_children | children], [new_links | links]},
      n_mixers
    )
  end

  defp create_audio_mixer(%MixerOptions{} = mixer_options) do
    %AudioMixer{
      caps: mixer_options.caps,
      frames_per_buffer: mixer_options.frames_per_buffer,
      prevent_clipping: mixer_options.prevent_clipping
    }
  end
end
