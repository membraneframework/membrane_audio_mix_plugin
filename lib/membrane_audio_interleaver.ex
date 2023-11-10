defmodule Membrane.AudioInterleaver do
  @moduledoc """
  Element responsible for interleaving several mono audio streams into single interleaved stream.
  All input streams should be in the same raw audio format, defined by `input_stream_format` option.

  Channels are interleaved in order given in `order` option - currently required, no default available.

  Each input pad should be identified with your custom id (using `via_in(Pad.ref(:input, your_example_id)` )
  """

  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias Membrane.AudioInterleaver.DoInterleave
  alias Membrane.Buffer
  alias Membrane.RawAudio

  def_options input_stream_format: [
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
              order: [
                type: :list,
                spec: [any()],
                description: """
                Order in which channels should be interleaved
                """
              ]

  def_input_pad :input,
    flow_control: :manual,
    availability: :on_request,
    demand_unit: :bytes,
    accepted_format: any_of(%RawAudio{channels: 1}, Membrane.RemoteStream),
    options: [
      offset: [
        spec: Time.t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  def_output_pad :output, flow_control: :manual, accepted_format: RawAudio

  @impl true
  def handle_init(_ctx, %__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        pads: %{},
        channels: length(options.order)
      })

    {[], state}
  end

  @impl true
  def handle_pad_added(pad, %{playback: :stopped}, state) do
    state = put_in(state, [:pads, pad], %{queue: <<>>, stream_ended: false})
    {[], state}
  end

  @impl true
  def handle_pad_added(_pad, %{playback: playback}, _state) do
    raise("All pads should be connected before starting the element!
      Pad added event received in playback state #{playback}.")
  end

  @impl true
  def handle_pad_removed(pad, _ctx, state) do
    state = Bunch.Access.delete_in(state, [:pads, pad])
    {[], state}
  end

  @impl true
  def handle_playing(
        _ctx,
        %{input_stream_format: %RawAudio{} = input_stream_format, channels: channels} = state
      ) do
    {[stream_format: {:output, %RawAudio{input_stream_format | channels: channels}}], state}
  end

  @impl true
  def handle_playing(_ctx, %{input_stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _ctx, %{channels: channels} = state) do
    do_handle_demand(div(size, channels), state)
  end

  @impl true
  def handle_demand(:output, _buffers_count, :buffers, _ctx, %{input_stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        buffers_count,
        :buffers,
        _ctx,
        %{frames_per_buffer: frames, input_stream_format: input_stream_format} = state
      ) do
    size = buffers_count * RawAudio.frames_to_bytes(frames, input_stream_format)
    do_handle_demand(size, state)
  end

  @impl true
  def handle_start_of_stream(pad, context, state) do
    offset = context.pads[pad].options.offset
    silence = RawAudio.silence(state.input_stream_format, offset)

    state =
      Bunch.Access.update_in(
        state,
        [:pads, pad],
        &%{&1 | queue: silence}
      )

    demand_fun = &max(0, &1 - byte_size(silence))
    {buffer, state} = interleave(state, min_open_queue_size(state.pads))

    {[demand: {pad, demand_fun}, buffer: buffer], state}
  end

  @impl true
  def handle_end_of_stream(pad, _ctx, state) do
    state = put_in(state, [:pads, pad, :stream_ended], true)

    all_streams_ended =
      state.pads
      |> Enum.map(fn {_pad, %{stream_ended: stream_ended}} -> stream_ended end)
      |> Enum.all?()

    if all_streams_ended do
      {buffer, state} = interleave(state, longest_queue_size(state.pads))
      {[buffer: buffer, end_of_stream: :output], state}
    else
      {buffer, state} = interleave(state, min_open_queue_size(state.pads))
      {[buffer: buffer], state}
    end
  end

  @impl true
  def handle_event(pad, event, _ctx, state) do
    Membrane.Logger.debug("Received event #{inspect(event)} on pad #{inspect(pad)}")

    {[], state}
  end

  @impl true
  def handle_buffer(
        pad,
        %Buffer{payload: payload},
        _ctx,
        %{input_stream_format: input_stream_format} = state
      ) do
    {new_queue_size, state} = enqueue_payload(payload, pad, state)

    if new_queue_size >= RawAudio.sample_size(input_stream_format) do
      {buffer, state} = interleave(state, min_open_queue_size(state.pads))
      {[buffer: buffer], state}
    else
      {[redemand: :output], state}
    end
  end

  @impl true
  def handle_stream_format(_pad, input_stream_format, _ctx, %{input_stream_format: nil} = state) do
    state = %{state | input_stream_format: input_stream_format}

    {[
       stream_format: {:output, %{input_stream_format | channels: state.channels}},
       redemand: :output
     ], state}
  end

  @impl true
  def handle_stream_format(
        _pad,
        %Membrane.RemoteStream{} = _input_stream_format,
        _ctx,
        %{input_stream_format: nil} = _state
      ) do
    raise """
    You need to specify `input_stream_format` in options if `Membrane.RemoteStream` will be received on the `:input` pad
    """
  end

  @impl true
  def handle_stream_format(
        _pad,
        input_stream_format,
        _ctx,
        %{input_stream_format: input_stream_format} = state
      ) do
    {[], state}
  end

  @impl true
  def handle_stream_format(_pad, %Membrane.RemoteStream{} = _input_stream_format, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(pad, input_stream_format, _ctx, state) do
    raise "received invalid stream_format on pad #{inspect(pad)}, expected: #{inspect(state.input_stream_format)}, got: #{inspect(input_stream_format)}"
  end

  # send demand to input pads that don't have a long enough queue
  defp do_handle_demand(size, %{pads: pads} = state) do
    pads
    |> Enum.map(fn {pad, %{queue: queue}} ->
      queue
      |> byte_size()
      |> then(&{:demand, {pad, max(0, size - &1)}})
    end)
    |> then(fn demands -> {demands, state} end)
  end

  defp interleave(
         %{input_stream_format: input_stream_format, pads: pads, order: order} = state,
         n_bytes
       ) do
    sample_size = RawAudio.sample_size(input_stream_format)

    n_bytes = trunc_to_whole_samples(n_bytes, sample_size)

    if n_bytes >= sample_size do
      pads = append_silence_if_needed(input_stream_format, pads, n_bytes)
      {payload, pads} = DoInterleave.interleave(n_bytes, sample_size, pads, order)
      buffer = {:output, %Buffer{payload: payload}}
      {buffer, %{state | pads: pads}}
    else
      {{:output, []}, state}
    end
  end

  # append silence to each queue shorter than min_length
  defp append_silence_if_needed(stream_format, pads, min_length) do
    pads
    |> Enum.map(fn {pad, %{queue: queue} = pad_value} ->
      {pad, %{pad_value | queue: do_append_silence(queue, min_length, stream_format)}}
    end)
    |> Map.new()
  end

  defp do_append_silence(queue, length_bytes, stream_format) do
    missing_frames = ceil((length_bytes - byte_size(queue)) / RawAudio.frame_size(stream_format))

    if missing_frames > 0 do
      silence = stream_format |> RawAudio.silence() |> String.duplicate(missing_frames)
      queue <> silence
    else
      queue
    end
  end

  # Returns minimum number of bytes present in all queues that haven't yet received end_of_stream message
  defp min_open_queue_size(pads) do
    pads
    |> Enum.reject(fn {_pad, %{stream_ended: stream_ended}} -> stream_ended end)
    |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
    |> Enum.min(fn -> 0 end)
  end

  defp longest_queue_size(pads) do
    pads
    |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
    |> Enum.max(fn -> 0 end)
  end

  # Returns the biggest multiple of `sample_size` that is not bigger than `size`
  defp trunc_to_whole_samples(size, sample_size)
       when is_integer(size) and is_integer(sample_size) do
    rest = rem(size, sample_size)
    size - rest
  end

  # add payload to proper pad's queue
  defp enqueue_payload(payload, pad_key, %{pads: pads} = state) do
    {new_queue_size, pads} =
      Map.get_and_update(
        pads,
        pad_key,
        fn %{queue: queue} = pad ->
          {byte_size(queue) + byte_size(payload), %{pad | queue: queue <> payload}}
        end
      )

    {new_queue_size, %{state | pads: pads}}
  end
end
