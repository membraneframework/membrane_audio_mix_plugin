defmodule Membrane.AudioMixer do
  @moduledoc """
  This element performs audio mixing.

  Audio format can be set as an element option or received through stream_format from input pads. All
  received stream_format have to be identical and match ones in element option (if that option is
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
  alias Membrane.RawAudio
  alias Membrane.Time
  alias Membrane.TimestampQueue

  def_options stream_format: [
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
    flow_control: :manual,
    accepted_format: RawAudio

  def_input_pad :input,
    flow_control: :manual,
    availability: :on_request,
    demand_unit: :bytes,
    accepted_format:
      any_of(
        %RawAudio{sample_format: sample_format}
        when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be],
        Membrane.RemoteStream
      ),
    options: [
      offset: [
        spec: Time.non_neg(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(_ctx, %__MODULE__{stream_format: stream_format} = options) do
    if options.native_mixer && !options.prevent_clipping do
      raise "Invalid element options, for native mixer only clipping preventing one is available"
    end

    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        pads_data: %{},
        mixer_state: initialize_mixer_state(stream_format, options),
        last_ts_sent: 0,
        queue: TimestampQueue.new(pause_demand_boundary: {:buffers, 1000})
      })

    {[], state}
  end

  @impl true
  def handle_pad_added(pad, ctx, state) do
    if ctx.pad_options.offset < 0 do
      raise """
      Wrong offset value: #{ctx.pad_options.offset}, audio mixer only allows offset value to be non negative.
      """
    end

    state = put_in(state, [:pads_data, pad], %{queue: <<>>, ready_to_mix?: false})
    {[], state}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    state = Bunch.Access.delete_in(state, [:pads_data, pad])
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, %{stream_format: %RawAudio{} = stream_format} = state) do
    {[stream_format: {:output, stream_format}], state}
  end

  def handle_playing(_ctx, %{stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _ctx, state) do
    frame_size = RawAudio.frame_size(state.stream_format)
    do_handle_demand(size + frame_size, state)
  end

  @impl true
  def handle_demand(:output, _buffers_count, :buffers, _ctx, %{stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        buffers_count,
        :buffers,
        _ctx,
        %{frames_per_buffer: frames, stream_format: stream_format} = state
      ) do
    size = buffers_count * RawAudio.frames_to_bytes(frames, stream_format)
    do_handle_demand(size, state)
  end

  @impl true
  def handle_start_of_stream(pad, ctx, state) do
    offset = ctx.pads[pad].options.offset

    silence =
      if state.synchronize_buffers?, do: <<>>, else: RawAudio.silence(state.stream_format, offset)

    # refactor this shitty flag below
    ready_to_mix? = not state.synchronize_buffers?

    state =
      put_in(
        state,
        [:pads_data, pad],
        %{queue: silence, offset: offset, ready_to_mix?: ready_to_mix?}
      )

    {[redemand: :output], state}
  end

  @impl true
  def handle_end_of_stream(pad, ctx, state) do
    state =
      case get_in(state, [:pads_data, pad]) do
        %{queue: <<>>} ->
          Bunch.Access.delete_in(state, [:pads_data, pad])

        _state ->
          state
      end

    {actions, state} = mix(ctx, state)

    # actions =
    #   if all_streams_ended?(ctx) do
    #     actions ++ [{:end_of_stream, :output}]
    #   else
    #     actions
    #   end

    {actions, state}
  end

  @impl true
  def handle_event(pad, event, _ctx, state) do
    Membrane.Logger.debug("Received event #{inspect(event)} on pad #{inspect(pad)}")

    {[], state}
  end

  @impl true
  def handle_buffer(
        pad_ref,
        buffer,
        ctx,
        state
      ) do
    ready_to_mix? = get_in(state.pads_data, [pad_ref, :ready_to_mix?])
    do_handle_buffer(pad_ref, buffer, ready_to_mix?, ctx, state)
  end

  defp do_handle_buffer(
         pad_ref,
         %Buffer{payload: payload, pts: pts},
         false,
         ctx,
         %{stream_format: stream_format, pads_data: pads_data, last_ts_sent: last_ts_sent} = state
       ) do
    offset = get_in(pads_data, [pad_ref, :offset])
    buffer_ts = pts + offset

    state =
      if buffer_ts >= last_ts_sent do
        diff = buffer_ts - last_ts_sent
        silence = RawAudio.silence(stream_format, diff)

        update_in(
          state,
          [:pads_data, pad_ref],
          &%{&1 | queue: silence <> payload, ready_to_mix?: true}
        )
      else
        state
      end

    size = byte_size(get_in(state, [:pads_data, pad_ref, :queue]))
    # frame_size = RawAudio.frame_size(stream_format)

    # mix_and_redemand(size, frame_size, ctx, state)

    {mix_actions, state} =
      if size >= RawAudio.frame_size(stream_format),
        do: mix(ctx, state),
        else: {[], state}

    {mix_actions ++ [redemand: :output], state}
  end

  defp do_handle_buffer(
         pad_ref,
         %Buffer{payload: payload},
         true,
         ctx,
         %{stream_format: stream_format} = state
       ) do
    {size, state} =
      get_and_update_in(state, [:pads_data, pad_ref], fn %{queue: queue} = pad_data ->
        {byte_size(queue) + byte_size(payload), %{pad_data | queue: queue <> payload}}
      end)

    {mix_actions, state} =
      if size >= RawAudio.frame_size(stream_format),
        do: mix(ctx, state),
        else: {[], state}

    {mix_actions ++ [redemand: :output], state}
  end

  @impl true
  def handle_stream_format(_pad, stream_format, _ctx, %{stream_format: nil} = state) do
    state = %{state | stream_format: stream_format}
    mixer_state = initialize_mixer_state(stream_format, state)

    {[stream_format: {:output, stream_format}, redemand: :output],
     %{state | mixer_state: mixer_state}}
  end

  @impl true
  def handle_stream_format(
        _pad,
        %Membrane.RemoteStream{} = _input_stream,
        _ctx,
        %{stream_format: nil} = _state
      ) do
    raise """
    You need to specify `stream_format` in options if `Membrane.RemoteStream` will be received on the `:input` pad
    """
  end

  @impl true
  def handle_stream_format(_pad, stream_format, _ctx, %{stream_format: stream_format} = state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(_pad, %Membrane.RemoteStream{} = _input_stream, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(pad, stream_format, _ctx, state) do
    raise(
      RuntimeError,
      "received invalid stream_format on pad #{inspect(pad)}, expected: #{inspect(state.stream_format)}, got: #{inspect(stream_format)}"
    )
  end

  # defp mix_and_redemand(size, frame_size, ctx, state) do
  #   {actions, state} =
  #     if size >= frame_size, do: mix(ctx, state), else: {[], state}

  #   {actions ++ [redemand: :output], state}
  # end

  defp initialize_mixer_state(nil, _state), do: nil

  defp initialize_mixer_state(stream_format, state) do
    mixer_module =
      if state.prevent_clipping do
        if state.native_mixer, do: NativeAdder, else: ClipPreventingAdder
      else
        Adder
      end

    mixer_module.init(stream_format)
  end

  defp do_handle_demand(size, %{pads_data: pads_data} = state) do
    actions =
      Enum.map(pads_data, fn {pad, %{queue: queue}} ->
        {:demand, {pad, max(0, size - byte_size(queue))}}
      end)

    {actions, state}
  end

  defp mix(ctx, %{stream_format: stream_format, pads_data: pads_data} = state) do
    sample_size = RawAudio.frame_size(stream_format)

    min_queue_size =
      pads_data
      |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
      |> Enum.min(fn -> 0 end)

    mix_size = min_queue_size - rem(min_queue_size, sample_size)

    {mixed_data, state} =
      if mix_size >= sample_size do
        {mixed_data, state} = mix_queued_data(mix_size, ctx, state)

        mixed_duration = RawAudio.bytes_to_time(mix_size, stream_format)
        state = Map.update!(state, :last_ts_sent, &(&1 + mixed_duration))

        {mixed_data, state}
      else
        {<<>>, state}
      end

    send_end_of_stream? = all_streams_ended?(ctx)

    {payload, state} =
      if send_end_of_stream? do
        {flushed_data, state} = apply_mixer_fun(:flush, [], state)
        {mixed_data <> flushed_data, state}
      else
        {mixed_data, state}
      end

    buffer_action =
      if payload != <<>>,
        do: [buffer: {:output, %Buffer{payload: payload}}],
        else: []

    actions =
      if send_end_of_stream?,
        do: buffer_action ++ [end_of_stream: :output],
        else: buffer_action

    {actions, state}
  end

  defp mix_queued_data(mix_size, ctx, state) do
    {payloads, pads_list} =
      state.pads_data
      |> Enum.map(fn
        {pad, %{queue: <<payload::binary-size(mix_size)>> <> tail} = data} ->
          {payload, {pad, %{data | queue: tail}}}
      end)
      |> Enum.unzip()

    sample_size = RawAudio.frame_size(state.stream_format)

    pads_data =
      pads_list
      |> Enum.reject(fn {pad, %{queue: queue}} ->
        ctx.pads[pad].end_of_stream? and byte_size(queue) < sample_size
      end)
      |> Map.new()

    state = %{state | pads_data: pads_data}

    apply_mixer_fun(:mix, [payloads], state)
  end

  defp all_streams_ended?(ctx) do
    Enum.all?(ctx.pads, fn {pad, data} -> pad == :output or data.end_of_stream? end)
  end

  defp apply_mixer_fun(fun_name, args, state) do
    Map.get_and_update!(state, :mixer_state, fn %mixer_module{} = mixer_state ->
      apply(mixer_module, fun_name, args ++ [mixer_state])
    end)
  end
end
