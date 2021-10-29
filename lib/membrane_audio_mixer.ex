defmodule Membrane.AudioMixer do
  @moduledoc """
  This element performs audio mixing.

  Audio format can be set as an element option or received through caps from input pads. All
  received caps have to be identical and match ones in element option (if that option is
  different from `nil`).

  Input pads can have offset - it tells how much silence should be added before first sample
  from that pad. Offset has to be positive.

  Mixer mixes only raw audio (PCM), so some parser may be needed to precede it in pipeline.
  """

  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias Membrane.AudioMixer.{Adder, ClipPreventingAdder}
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw
  alias Membrane.Caps.Matcher
  alias Membrane.Time

  @supported_caps {Raw,
                   format: Matcher.one_of([:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be])}

  def_options caps: [
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

  def_output_pad :output,
    mode: :pull,
    availability: :always,
    caps: Raw

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

  @impl true
  def handle_init(%__MODULE__{caps: caps} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:pads, %{})
      |> then(&if caps == nil, do: &1, else: initialize_mixer_state(caps, &1))

    {:ok, state}
  end

  @impl true
  def handle_pad_added(pad, _context, state) do
    state =
      Bunch.Access.put_in(
        state,
        [:pads, pad],
        %{queue: <<>>, stream_ended: false}
      )

    {:ok, state}
  end

  @impl true
  def handle_pad_removed(pad, _context, state) do
    state = Bunch.Access.delete_in(state, [:pads, pad])

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_context, %{caps: %Raw{} = caps} = state) do
    {{:ok, caps: {:output, caps}}, state}
  end

  def handle_prepared_to_playing(_context, %{caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _context, state) do
    do_handle_demand(size, state)
  end

  @impl true
  def handle_demand(:output, _buffers_count, :buffers, _context, %{caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(
        :output,
        buffers_count,
        :buffers,
        _context,
        %{frames_per_buffer: frames, caps: caps} = state
      ) do
    size = buffers_count * Raw.frames_to_bytes(frames, caps)
    do_handle_demand(size, state)
  end

  @impl true
  def handle_start_of_stream(pad, context, state) do
    offset = context.pads[pad].options.offset
    silence = Raw.sound_of_silence(state.caps, offset)

    state =
      Bunch.Access.update_in(
        state,
        [:pads, pad],
        &%{&1 | queue: silence}
      )

    {actions, state} = mix_and_get_actions(state)
    {{:ok, actions ++ [{:redemand, :output}]}, state}
  end

  @impl true
  def handle_end_of_stream(pad, _context, state) do
    state =
      case Bunch.Access.get_in(state, [:pads, pad]) do
        %{queue: <<>>} ->
          Bunch.Access.delete_in(state, [:pads, pad])

        _state ->
          Bunch.Access.update_in(
            state,
            [:pads, pad],
            &%{&1 | stream_ended: true}
          )
      end

    {actions, state} = mix_and_get_actions(state)

    if all_streams_ended?(state) do
      {{:ok, actions ++ [{:end_of_stream, :output}]}, state}
    else
      {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_event(pad, event, _context, state) do
    Membrane.Logger.debug("Received event #{inspect(event)} on pad #{inspect(pad)}")

    {:ok, state}
  end

  @impl true
  def handle_process(
        pad_ref,
        %Buffer{payload: payload},
        _context,
        %{caps: caps, pads: pads} = state
      ) do
    time_frame = Raw.frame_size(caps)

    {size, pads} =
      Map.get_and_update(
        pads,
        pad_ref,
        fn %{queue: queue} = pad ->
          {byte_size(queue) + byte_size(payload), %{pad | queue: queue <> payload}}
        end
      )

    if size >= time_frame do
      {actions, state} = mix_and_get_actions(%{state | pads: pads})
      actions = if actions == [], do: [redemand: :output], else: actions
      {{:ok, actions}, state}
    else
      {{:ok, redemand: :output}, %{state | pads: pads}}
    end
  end

  @impl true
  def handle_caps(_pad, caps, _context, %{caps: nil} = state) do
    state = state |> Map.put(:caps, caps) |> then(&initialize_mixer_state(caps, &1))

    {{:ok, caps: {:output, caps}, redemand: :output}, state}
  end

  @impl true
  def handle_caps(_pad, caps, _context, %{caps: caps} = state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(pad, caps, _context, state) do
    raise(
      RuntimeError,
      "received invalid caps on pad #{inspect(pad)}, expected: #{inspect(state.caps)}, got: #{inspect(caps)}"
    )
  end

  defp initialize_mixer_state(caps, state) do
    mixer_module = if state.prevent_clipping, do: ClipPreventingAdder, else: Adder
    mixer_state = mixer_module.init(caps)

    Map.put(state, :mixer_state, mixer_state)
  end

  defp do_handle_demand(size, %{pads: pads} = state) do
    pads
    |> Enum.map(fn {pad, %{queue: queue}} ->
      queue
      |> byte_size()
      |> then(&{:demand, {pad, max(0, size - &1)}})
    end)
    |> then(fn demands -> {{:ok, demands}, state} end)
  end

  defp mix_and_get_actions(%{caps: caps, pads: pads} = state) do
    time_frame = Raw.frame_size(caps)
    mix_size = get_mix_size(pads, time_frame)

    {payload, state} =
      if mix_size >= time_frame do
        {payload, pads, state} = mix(pads, mix_size, state)
        pads = remove_finished_pads(pads, time_frame)
        state = %{state | pads: pads}

        {payload, state}
      else
        {<<>>, state}
      end

    {payload, state} =
      if all_streams_ended?(state) do
        {flushed, state} = flush_mixer(state)
        {payload <> flushed, state}
      else
        {payload, state}
      end

    actions = if payload == <<>>, do: [], else: [buffer: {:output, %Buffer{payload: payload}}]
    {actions, state}
  end

  defp get_mix_size(pads, time_frame) do
    pads
    |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
    |> Enum.min(fn -> 0 end)
    |> int_part(time_frame)
  end

  # Returns the biggest multiple of `divisor` that is not bigger than `number`
  defp int_part(number, divisor) when is_integer(number) and is_integer(divisor) do
    rest = rem(number, divisor)
    number - rest
  end

  defp mix(pads, mix_size, state) do
    {payloads, pads_list} =
      pads
      |> Enum.map(fn
        {pad, %{queue: <<payload::binary-size(mix_size)>> <> queue} = data} ->
          {payload, {pad, %{data | queue: queue}}}
      end)
      |> Enum.unzip()

    {payload, state} = mix_payloads(payloads, state)
    pads = Map.new(pads_list)

    {payload, pads, state}
  end

  defp all_streams_ended?(%{pads: pads}) do
    pads
    |> Enum.map(fn {_pad, %{stream_ended: stream_ended}} -> stream_ended end)
    |> Enum.all?()
  end

  defp remove_finished_pads(pads, time_frame) do
    pads
    |> Enum.flat_map(fn
      {_pad, %{queue: queue, stream_ended: true}} when byte_size(queue) < time_frame -> []
      pad_data -> [pad_data]
    end)
    |> Map.new()
  end

  defp mix_payloads(payloads, %{mixer_state: %module{} = mixer_state} = state) do
    {payload, mixer_state} = module.mix(payloads, mixer_state)
    state = %{state | mixer_state: mixer_state}
    {payload, state}
  end

  defp flush_mixer(%{mixer_state: %module{} = mixer_state} = state) do
    {payload, mixer_state} = module.flush(mixer_state)
    state = %{state | mixer_state: mixer_state}
    {payload, state}
  end
end
