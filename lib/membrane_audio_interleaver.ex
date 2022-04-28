defmodule Membrane.AudioInterleaver do
  @moduledoc """
  Element responsible for interleaving several mono audio streams into single interleaved stream.
  All input streams should be in the same raw audio format, defined by `input_caps` option.

  Channels are interleaved in order given in `order` option - currently required, no default available.

  Each input pad should be identified with your custom id (using `via_in(Pad.ref(:input, your_example_id)` )
  """

  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias Membrane.AudioInterleaver.DoInterleave
  alias Membrane.Buffer
  alias Membrane.RawAudio

  def_options input_caps: [
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

  def_output_pad :output,
    mode: :pull,
    availability: :always,
    caps: RawAudio

  def_input_pad :input,
    mode: :pull,
    availability: :on_request,
    demand_unit: :bytes,
    caps: [{RawAudio, channels: 1}, Membrane.RemoteStream],
    options: [
      offset: [
        spec: Time.t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        pads: %{},
        channels: length(options.order)
      })

    {:ok, state}
  end

  @impl true
  def handle_pad_added(pad, %{playback_state: :stopped}, state) do
    state = put_in(state, [:pads, pad], %{queue: <<>>, stream_ended: false})
    {:ok, state}
  end

  @impl true
  def handle_pad_added(_pad, %{playback_state: playback_state}, _state) do
    raise("All pads should be connected before starting the element!
      Pad added event received in playback state #{playback_state}.")
  end

  @impl true
  def handle_pad_removed(pad, _context, state) do
    state = Bunch.Access.delete_in(state, [:pads, pad])
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(
        _context,
        %{input_caps: %RawAudio{} = input_caps, channels: channels} = state
      ) do
    {{:ok, caps: {:output, %RawAudio{input_caps | channels: channels}}}, state}
  end

  @impl true
  def handle_prepared_to_playing(_context, %{input_caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _context, %{channels: channels} = state) do
    do_handle_demand(div(size, channels), state)
  end

  @impl true
  def handle_demand(:output, _buffers_count, :buffers, _context, %{input_caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(
        :output,
        buffers_count,
        :buffers,
        _context,
        %{frames_per_buffer: frames, input_caps: input_caps} = state
      ) do
    size = buffers_count * RawAudio.frames_to_bytes(frames, input_caps)
    do_handle_demand(size, state)
  end

  @impl true
  def handle_start_of_stream(pad, context, state) do
    offset = context.pads[pad].options.offset
    silence = RawAudio.silence(state.input_caps, offset)

    state =
      Bunch.Access.update_in(
        state,
        [:pads, pad],
        &%{&1 | queue: silence}
      )

    demand_fun = &max(0, &1 - byte_size(silence))
    {buffer, state} = interleave(state, min_open_queue_size(state.pads))

    {{:ok, demand: {pad, demand_fun}, buffer: buffer}, state}
  end

  @impl true
  def handle_end_of_stream(pad, _context, state) do
    state = put_in(state, [:pads, pad, :stream_ended], true)

    all_streams_ended =
      state.pads
      |> Enum.map(fn {_pad, %{stream_ended: stream_ended}} -> stream_ended end)
      |> Enum.all?()

    if all_streams_ended do
      {buffer, state} = interleave(state, longest_queue_size(state.pads))
      {{:ok, buffer: buffer, end_of_stream: :output}, state}
    else
      {buffer, state} = interleave(state, min_open_queue_size(state.pads))
      {{:ok, buffer: buffer}, state}
    end
  end

  @impl true
  def handle_event(pad, event, _context, state) do
    Membrane.Logger.debug("Received event #{inspect(event)} on pad #{inspect(pad)}")

    {:ok, state}
  end

  @impl true
  def handle_process(
        pad,
        %Buffer{payload: payload},
        _context,
        %{input_caps: input_caps} = state
      ) do
    {new_queue_size, state} = enqueue_payload(payload, pad, state)

    if new_queue_size >= RawAudio.sample_size(input_caps) do
      {buffer, state} = interleave(state, min_open_queue_size(state.pads))
      {{:ok, buffer: buffer}, state}
    else
      {{:ok, redemand: :output}, state}
    end
  end

  @impl true
  def handle_caps(_pad, input_caps, _context, %{input_caps: nil} = state) do
    state = %{state | input_caps: input_caps}

    {{:ok, caps: {:output, %{input_caps | channels: state.channels}}, redemand: :output}, state}
  end

  @impl true
  def handle_caps(
        _pad,
        %Membrane.RemoteStream{} = _input_caps,
        _context,
        %{input_caps: nil} = _state
      ) do
    raise """
    You need to specify `input_caps` in options if `Membrane.RemoteStream` will be received on the `:input` pad
    """
  end

  @impl true
  def handle_caps(_pad, input_caps, _context, %{input_caps: input_caps} = state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(_pad, %Membrane.RemoteStream{} = _input_caps, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_caps(pad, input_caps, _context, state) do
    raise(
      RuntimeError,
      "received invalid caps on pad #{inspect(pad)}, expected: #{inspect(state.input_caps)}, got: #{inspect(input_caps)}"
    )
  end

  # send demand to input pads that don't have a long enough queue
  defp do_handle_demand(size, %{pads: pads} = state) do
    pads
    |> Enum.map(fn {pad, %{queue: queue}} ->
      queue
      |> byte_size()
      |> then(&{:demand, {pad, max(0, size - &1)}})
    end)
    |> then(fn demands -> {{:ok, demands}, state} end)
  end

  defp interleave(%{input_caps: input_caps, pads: pads, order: order} = state, n_bytes) do
    sample_size = RawAudio.sample_size(input_caps)

    n_bytes = trunc_to_whole_samples(n_bytes, sample_size)

    if n_bytes >= sample_size do
      pads = append_silence_if_needed(input_caps, pads, n_bytes)
      {payload, pads} = DoInterleave.interleave(n_bytes, sample_size, pads, order)
      buffer = {:output, %Buffer{payload: payload}}
      {buffer, %{state | pads: pads}}
    else
      {{:output, []}, state}
    end
  end

  # append silence to each queue shorter than min_length
  defp append_silence_if_needed(caps, pads, min_length) do
    pads
    |> Enum.map(fn {pad, %{queue: queue} = pad_value} ->
      {pad, %{pad_value | queue: do_append_silence(queue, min_length, caps)}}
    end)
    |> Map.new()
  end

  defp do_append_silence(queue, length_bytes, caps) do
    missing_frames = ceil((length_bytes - byte_size(queue)) / RawAudio.frame_size(caps))

    if missing_frames > 0 do
      silence = caps |> RawAudio.silence() |> String.duplicate(missing_frames)
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
