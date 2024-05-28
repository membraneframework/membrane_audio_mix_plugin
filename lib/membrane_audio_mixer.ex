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
  alias Membrane.RemoteStream
  alias Membrane.Time

  def_options stream_format: [
                spec: RawAudio.t(),
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                """,
                default: nil
              ],
              frames_per_buffer: [
                spec: pos_integer(),
                description: """
                Assumed number of raw audio frames in each buffer.
                Used when converting demand from buffers into bytes.
                """,
                default: 2048
              ],
              prevent_clipping: [
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
                spec: boolean(),
                description: """
                The value determines if mixer should use NIFs for mixing audio. Only
                clip preventing version of native mixer is available.
                See `Membrane.AudioMixer.NativeAdder`.
                """,
                default: false
              ],
              synchronize_buffers?: [
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
        RemoteStream
      ),
    options: [
      offset: [
        spec: Time.non_neg(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    if options.native_mixer and not options.prevent_clipping do
      raise "Invalid element options, for native mixer only clipping preventing one is available"
    end

    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{pads_data: %{}, last_ts_sent: 0, sample_size: nil, mixer_state: nil})

    {[], state}
  end

  @impl true
  def handle_pad_added(pad, ctx, state) do
    offset = ctx.pad_options.offset

    if offset < 0 do
      raise "Wrong offset value: #{offset}, audio mixer only allows offset value to be non negative."
    end

    pad_data = %{queue: <<>>, synchronized?: false, offset: offset}
    state = put_in(state, [:pads_data, pad], pad_data)

    {[], state}
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    state = Bunch.Access.delete_in(state, [:pads_data, pad])
    {[], state}
  end

  @impl true
  def handle_demand(:output, _size, _demand, _ctx, %{stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _ctx, state) do
    sample_size = state.sample_size || RawAudio.frame_size(state.stream_format)
    do_handle_demand(size + sample_size, state)
  end

  @impl true
  def handle_demand(:output, buffers_count, :buffers, _ctx, state) do
    output_payload_size = RawAudio.frames_to_bytes(state.frames_per_buffer, state.stream_format)
    do_handle_demand(buffers_count * output_payload_size, state)
  end

  defp do_handle_demand(target_queues_size, state) do
    actions =
      state.pads_data
      |> Enum.map(fn {pad, %{queue: queue}} ->
        demand = max(0, target_queues_size - byte_size(queue))
        {:demand, {pad, demand}}
      end)

    {actions, state}
  end

  @impl true
  def handle_event(pad, event, _ctx, state) do
    Membrane.Logger.debug("Received event #{inspect(event)} on pad #{inspect(pad)}")
    {[], state}
  end

  @impl true
  def handle_stream_format(pad, stream_format, ctx, state) do
    {actions, state} =
      cond do
        ctx.pads.output.stream_format != nil -> {[], state}
        state.stream_format != nil -> set_stream_format(state.stream_format, state)
        true -> set_stream_format(stream_format, state)
      end

    :ok = validate_input_stream_format!(pad, stream_format, state)

    {actions, state}
  end

  defp set_stream_format(%RemoteStream{}, _state) do
    raise """
    You need to specify `stream_format` in options if `Membrane.RemoteStream` will be received on the `:input` \
    pad and you cannot pas `Membrane.RemoteStream{}` in this option.
    """
  end

  defp set_stream_format(stream_format, state) when stream_format != nil do
    state =
      %{
        state
        | stream_format: stream_format,
          sample_size: RawAudio.frame_size(stream_format),
          mixer_state: initialize_mixer_state(stream_format, state)
      }

    {[stream_format: {:output, stream_format}, redemand: :output], state}
  end

  defp validate_input_stream_format!(_pad, %RemoteStream{}, _state), do: :ok

  defp validate_input_stream_format!(_pad, stream_format, %{stream_format: stream_format}),
    do: :ok

  defp validate_input_stream_format!(pad, stream_format, state) do
    raise """
    Received invalid stream_format on pad #{inspect(pad)}, expected: #{inspect(state.stream_format)}, \
    got: #{inspect(stream_format)}
    """
  end

  defp initialize_mixer_state(stream_format, state) do
    cond do
      not state.prevent_clipping -> Adder.init(stream_format)
      state.native_mixer -> NativeAdder.init(stream_format)
      true -> ClipPreventingAdder.init(stream_format)
    end
  end

  @impl true
  def handle_buffer(pad, buffer, ctx, state) do
    pad_data =
      with %{synchronized?: false} = pad_data <- Map.fetch!(state.pads_data, pad) do
        silence_duration =
          if state.synchronize_buffers?,
            do: buffer.pts + pad_data.offset - state.last_ts_sent,
            else: pad_data.offset

        silence_payload =
          if silence_duration >= 0,
            do: RawAudio.silence(state.stream_format, silence_duration),
            else: <<>>

        %{pad_data | synchronized?: true, queue: silence_payload}
      end
      |> Map.update!(:queue, &(&1 <> buffer.payload))

    state = put_in(state, [:pads_data, pad], pad_data)

    {mix_actions, state} =
      if byte_size(pad_data.queue) >= state.sample_size,
        do: mix(ctx, state),
        else: {[], state}

    {mix_actions ++ [redemand: :output], state}
  end

  @impl true
  def handle_end_of_stream(pad, ctx, state) do
    queue_size = get_in(state, [:pads_data, pad, :queue]) |> byte_size()

    state =
      if queue_size < state.sample_size,
        do: state |> Bunch.Access.delete_in([:pads_data, pad]),
        else: state

    mix(ctx, state)
  end

  defp mix(ctx, %{stream_format: stream_format} = state) do
    mix_size = calculate_mix_size(state)
    buffer_pts = state.last_ts_sent

    {mixed_data, state} =
      if mix_size >= state.sample_size do
        {payloads, state} = pop_payloads_from_queues(mix_size, ctx, state)
        {mixed_data, state} = apply_mixer_fun(:mix, [payloads], state)

        mixed_data_duration = RawAudio.bytes_to_time(mix_size, stream_format)
        state = Map.update!(state, :last_ts_sent, &(&1 + mixed_data_duration))

        {mixed_data, state}
      else
        {<<>>, state}
      end

    send_end_of_stream? =
      ctx.pads
      |> Enum.all?(fn {pad, data} -> pad == :output or data.end_of_stream? end)

    {output_payload, state} =
      if send_end_of_stream? do
        {flushed_data, state} = apply_mixer_fun(:flush, [], state)
        {mixed_data <> flushed_data, state}
      else
        {mixed_data, state}
      end

    buffer_action =
      if output_payload != <<>>,
        do: [buffer: {:output, %Buffer{payload: output_payload, pts: buffer_pts}}],
        else: []

    actions =
      if send_end_of_stream?,
        do: buffer_action ++ [end_of_stream: :output],
        else: buffer_action

    {actions, state}
  end

  defp calculate_mix_size(state) do
    min_queue_size =
      state.pads_data
      |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
      |> Enum.min(fn -> 0 end)

    min_queue_size - rem(min_queue_size, state.sample_size)
  end

  defp pop_payloads_from_queues(mix_size, ctx, state) do
    {payloads, pads_list} =
      state.pads_data
      |> Enum.map(fn
        {pad, %{queue: <<payload::binary-size(mix_size)>> <> tail} = data} ->
          {payload, {pad, %{data | queue: tail}}}
      end)
      |> Enum.unzip()

    pads_data =
      pads_list
      |> Enum.reject(fn {pad, %{queue: queue}} ->
        ctx.pads[pad].end_of_stream? and byte_size(queue) < state.sample_size
      end)
      |> Map.new()

    {payloads, %{state | pads_data: pads_data}}
  end

  defp apply_mixer_fun(fun_name, args, state) do
    Map.get_and_update!(state, :mixer_state, fn %mixer_module{} = mixer_state ->
      apply(mixer_module, fun_name, args ++ [mixer_state])
    end)
  end
end
