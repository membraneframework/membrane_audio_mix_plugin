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

  alias Membrane.AudioMixer.{Adder, ClipPreventingAdder, NativeAdder}
  alias Membrane.Buffer
  alias Membrane.Caps.Matcher
  alias Membrane.RawAudio
  alias Membrane.Time

  @supported_caps [
    {RawAudio,
     sample_format: Matcher.one_of([:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be])},
    Membrane.RemoteStream
  ]

  def_options caps: [
                type: :struct,
                spec: RawAudio.t(),
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
              ],
              native_mixer: [
                type: :boolean,
                spec: boolean(),
                description: """
                The value determines if mixer should use NIFs for mixing audio. Only
                clip preventing version of native mixer is available.
                See `Membrane.AudioMixer.NativeAdder`.
                """,
                default: false
              ],
              synchronize_buffers?: [
                type: :boolean,
                spec: boolean(),
                description: """
                The value determines if mixer should synchronize buffers based on pts values.
                - If true, mixer will synchronize buffers based on its pts values. If buffer pts value is lower then the current
                mixing time (last_ts_sent) it will be dropped.
                - If false, mixer will take all incoming buffers no matter what pts they have and put it in the queue.
                """,
                default: false
              ]

  def_output_pad :output,
    demand_mode: :auto,
    availability: :always,
    caps: RawAudio

  def_input_pad :input,
    demand_mode: :auto,
    availability: :on_request,
    demand_unit: :buffers,
    caps: @supported_caps,
    options: [
      offset: [
        spec: Time.non_neg_t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(%__MODULE__{caps: caps} = options) do
    if options.native_mixer && !options.prevent_clipping do
      raise("Invalid element options, for native mixer only clipping preventing one is available")
    else
      state =
        options
        |> Map.from_struct()
        |> Map.put(:pads, %{})
        |> Map.put(:mixer_state, initialize_mixer_state(caps, options))
        |> Map.put(:last_ts_sent, 0)

      {:ok, state}
    end
  end

  @impl true
  def handle_pad_added(pad, context, state) do
    offset = context.pads[pad].options.offset

    if offset < 0,
      do:
        raise(
          "Wrong offset value: #{offset}, audio mixer only allows offset value to be non negative."
        )

    state =
      put_in(
        state,
        [:pads, pad],
        %{queue: <<>>, ready_to_mix?: false}
      )

    {:ok, state}
  end

  @impl true
  def handle_pad_removed(pad, _context, state) do
    state = Bunch.Access.delete_in(state, [:pads, pad])

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_context, %{caps: %RawAudio{} = caps} = state) do
    {{:ok, caps: {:output, caps}}, state}
  end

  def handle_prepared_to_playing(_context, %{caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_stopped(_context, state) do
    {:ok, %{state | mixer_state: nil}}
  end

  # @impl true
  # def handle_demand(:output, size, :bytes, _context, state) do
  #   do_handle_demand(size, state)
  # end

  # @impl true
  # def handle_demand(:output, _buffers_count, :buffers, _context, %{caps: nil} = state) do
  #   {:ok, state}
  # end

  # @impl true
  # def handle_demand(
  #       :output,
  #       buffers_count,
  #       :buffers,
  #       _context,
  #       %{frames_per_buffer: frames, caps: caps} = state
  #     ) do
  #   size = buffers_count * RawAudio.frames_to_bytes(frames, caps)
  #   do_handle_demand(size, state)
  # end

  @impl true
  def handle_start_of_stream(pad, context, state) do
    offset = context.pads[pad].options.offset
    silence = if state.synchronize_buffers?, do: <<>>, else: RawAudio.silence(state.caps, offset)
    ready_to_mix? = not state.synchronize_buffers?

    state =
      put_in(
        state,
        [:pads, pad],
        %{queue: silence, offset: offset, ready_to_mix?: ready_to_mix?}
      )

    {:ok, state}
  end

  @impl true
  def handle_end_of_stream(pad, context, state) do
    state =
      case get_in(state, [:pads, pad]) do
        %{queue: <<>>} ->
          Bunch.Access.delete_in(state, [:pads, pad])

        _state ->
          state
      end

    {actions, state} = mix_and_get_actions(context, state)

    if all_streams_ended?(context) do
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
        buffer,
        context,
        state
      ) do
    ready_to_mix? = get_in(state.pads, [pad_ref, :ready_to_mix?])
    do_handle_process(pad_ref, buffer, ready_to_mix?, context, state)
  end

  defp do_handle_process(
         pad_ref,
         %Buffer{payload: payload, pts: pts},
         false,
         context,
         %{caps: caps, pads: pads, last_ts_sent: last_ts_sent} = state
       ) do
    offset = get_in(pads, [pad_ref, :offset])
    buffer_ts = pts + offset

    state =
      if buffer_ts >= last_ts_sent do
        diff = buffer_ts - last_ts_sent
        silence = RawAudio.silence(caps, diff)

        update_in(
          state,
          [:pads, pad_ref],
          &%{&1 | queue: silence <> payload, ready_to_mix?: true}
        )
      else
        state
      end

    size = byte_size(get_in(state, [:pads, pad_ref, :queue]))
    time_frame = RawAudio.frame_size(caps)

    mix_or_redemand(size, time_frame, context, state)
  end

  defp do_handle_process(
         pad_ref,
         %Buffer{payload: payload},
         true,
         context,
         %{caps: caps, pads: pads} = state
       ) do
    {size, pads} =
      Map.get_and_update(
        pads,
        pad_ref,
        fn %{queue: queue} = pad ->
          {byte_size(queue) + byte_size(payload), %{pad | queue: queue <> payload}}
        end
      )

    time_frame = RawAudio.frame_size(caps)
    mix_or_redemand(size, time_frame, context, %{state | pads: pads})
  end

  @impl true
  def handle_caps(_pad, caps, _context, %{caps: nil} = state) do
    state = %{state | caps: caps}
    mixer_state = initialize_mixer_state(caps, state)

    {{:ok, caps: {:output, caps}}, %{state | mixer_state: mixer_state}}
  end

  @impl true
  def handle_caps(
        _pad,
        %Membrane.RemoteStream{} = _input_caps,
        _context,
        %{input_caps: nil} = _state
      ) do
    raise """
    You need to specify `caps` in options if `Membrane.RemoteStream` will be received on the `:input` pad
    """
  end

  @impl true
  def handle_caps(_pad, caps, _context, %{caps: caps} = state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(_pad, %Membrane.RemoteStream{} = _input_caps, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(pad, caps, _context, state) do
    raise(
      RuntimeError,
      "received invalid caps on pad #{inspect(pad)}, expected: #{inspect(state.caps)}, got: #{inspect(caps)}"
    )
  end

  defp mix_or_redemand(size, time_frame, context, state) do
    if size >= time_frame do
      {actions, state} = mix_and_get_actions(context, state)
      actions = if actions == [], do: [], else: actions
      {{:ok, actions}, state}
    else
      {:ok, state}
    end
  end

  defp initialize_mixer_state(nil, _state), do: nil

  defp initialize_mixer_state(caps, state) do
    mixer_module =
      if state.prevent_clipping do
        if state.native_mixer, do: NativeAdder, else: ClipPreventingAdder
      else
        Adder
      end

    mixer_module.init(caps)
  end

  # defp do_handle_demand(size, %{pads: pads} = state) do
  #   pads
  #   |> Enum.map(fn {pad, %{queue: queue}} ->
  #     queue
  #     |> byte_size()
  #     |> then(&{:demand, {pad, max(0, size - &1)}})
  #   end)
  #   |> then(fn demands -> {{:ok, demands}, state} end)
  # end

  defp mix_and_get_actions(context, %{caps: caps, pads: pads} = state) do
    time_frame = RawAudio.frame_size(caps)
    mix_size = get_mix_size(pads, time_frame)

    {payload, state} =
      if mix_size >= time_frame do
        {payload, pads, state} = mix(pads, mix_size, state)
        pads = remove_finished_pads(context, pads, time_frame)
        mix_time = RawAudio.bytes_to_time(mix_size, caps)
        state = %{state | pads: pads, last_ts_sent: state.last_ts_sent + mix_time}

        {payload, state}
      else
        {<<>>, state}
      end

    {payload, state} =
      if all_streams_ended?(context) do
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
    |> Enum.filter(fn {pad_name, _info} -> pad_name != :output end)
    |> Enum.map(fn {_pad, %{end_of_stream?: end_of_stream?}} -> end_of_stream? end)
    |> Enum.all?()
  end

  defp remove_finished_pads(context, pads, time_frame) do
    pads
    |> Enum.flat_map(&maybe_remove_pad(time_frame, context, &1))
    |> Map.new()
  end

  defp maybe_remove_pad(time_frame, context, {pad, %{queue: queue}} = pad_data) do
    end_of_stream = Map.get(context.pads, pad).end_of_stream?
    to_short_to_mix = byte_size(queue) < time_frame
    if end_of_stream and to_short_to_mix, do: [], else: [pad_data]
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
