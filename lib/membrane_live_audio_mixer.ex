defmodule Membrane.LiveAudioMixer do
  @moduledoc """
  This element performs audio mixing for live streams.

  Live Audio Mixer starts to mix audio after the first input pad is added or, if `latency` option is set to `nil`, when `start_mixing` notification is send.
  From this point, the mixer will produce an audio until `:schedule_eos` notification and `:end_of_stream` are received on all input pads.

  Mixer mixes only raw audio (PCM), so some parser may be needed to precede it in pipeline.

  ## Notifications

  - `:schedule_eos` -  mixer will send `end_of_stream` when it processes all input streams.
    After sending `:schedule_eos` mixer will raise if it gets a new input pad.

  - {`:start_mixing`, latency} - mixer will start mixing audio after latency (non_neg_integer()).
    Audio that will come before the notification will be buffered.

  Input pads can have offset - it tells how much timestamps differ from mixer time.
  """

  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias Membrane.AudioMixer.{Adder, ClipPreventingAdder, NativeAdder}
  alias Membrane.Buffer
  alias Membrane.LiveAudioMixer.LiveQueue
  alias Membrane.RawAudio
  alias Membrane.Time

  @interval Membrane.Time.milliseconds(20)

  def_options prevent_clipping: [
                spec: boolean(),
                description: """
                Defines how the mixer should act in the case when an overflow happens.
                - If true, the wave will be scaled down, so a peak will become the maximal
                value of the sample in the format. See `Membrane.AudioMixer.ClipPreventingAdder`.
                - If false, overflow will be clipped to the maximal value of the sample in
                the format. See `Membrane.AudioMixer.Adder`.
                """,
                default: false
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
              latency: [
                spec: non_neg_integer() | nil,
                description: """
                The value determines after what time the clock will start interval that mixes audio in real time.
                Latency is crucial to quality of output audio, the smaller the value, the more packets will be lost.
                But the bigger the value, the bigger the latency of stream.

                Audio Mixer allows starting mixing earlier with parent_notification `:start_mixing`.
                In this case, stream_format has to be passed through options.

                If notification `:start_mixing` is sent after mixing has started, the message will be discarded

                Start mixing manually:
                  * set latency to nil
                  * mixing has to be started manually by sending`:start_mixing` notification.
                """,
                default: Membrane.Time.milliseconds(200),
                inspector: &Time.inspect/1
              ],
              stream_format: [
                spec: RawAudio.t() | nil,
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                It is necessary if `latency` is set to nil.
                """,
                default: nil
              ]

  def_output_pad :output, accepted_format: RawAudio

  def_input_pad :input,
    availability: :on_request,
    accepted_format:
      %RawAudio{sample_format: sample_format}
      when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be],
    options: [
      offset: [
        spec: Time.non_neg(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(_ctx, options) do
    # TODO: native and prevent_clipping adder enqueue silence.
    # in live mixer we want to immediately return added audio
    if options.native_mixer or options.prevent_clipping do
      Membrane.Logger.warning("""
      Leaving options prevent_clipping and native_mixer as defaults is recommended.
      In other case silence will be enqueued by mixer and send only when there will be some sound"
      """)
    end

    cond do
      options.native_mixer && !options.prevent_clipping ->
        raise "Invalid element options, for native mixer only clipping preventing one is available"

      options.latency == nil and options.stream_format == nil ->
        raise "Stream format has to be set to start mixing manually"

      true ->
        state =
          options
          |> Map.from_struct()
          |> Map.put(:mixer_state, nil)
          |> Map.put(:live_queue, nil)
          |> Map.put(:end_of_stream?, false)
          |> Map.put(:started?, false)
          |> Map.put(:eos_scheduled, false)

        {mixer_state, live_queue} =
          if is_nil(options.stream_format),
            do: {nil, nil},
            else:
              {initialize_mixer_state(options.stream_format, state),
               LiveQueue.init(options.stream_format)}

        {[], %{state | live_queue: live_queue, mixer_state: mixer_state}}
    end
  end

  @impl true
  def handle_playing(_context, %{stream_format: %RawAudio{} = stream_format} = state) do
    {[stream_format: {:output, stream_format}], state}
  end

  def handle_playing(_context, %{stream_format: nil} = state) do
    {[], state}
  end

  @impl true
  def handle_pad_added(_pad, _context, %{end_of_stream?: true}),
    do:
      raise(
        "Can't add input pad after scheduling eos and receiving end of stream on all already connected input pads"
      )

  @impl true
  def handle_pad_added(_pad, _context, %{end_of_stream?: false} = state), do: {[], state}

  @impl true
  def handle_stream_format(_pad, stream_format, _context, %{stream_format: nil} = state) do
    state = %{state | stream_format: stream_format}
    mixer_state = initialize_mixer_state(stream_format, state)
    live_queue = LiveQueue.init(stream_format)

    {[stream_format: {:output, stream_format}],
     %{state | mixer_state: mixer_state, live_queue: live_queue}}
  end

  @impl true
  def handle_stream_format(_pad, stream_format, _context, %{stream_format: stream_format} = state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(pad, stream_format, _context, state) do
    raise(
      RuntimeError,
      "received invalid stream_format on pad #{inspect(pad)}, expected: #{inspect(state.stream_format)}, got: #{inspect(stream_format)}"
    )
  end

  @impl true
  def handle_start_of_stream(
        Pad.ref(:input, pad_id) = pad,
        context,
        %{live_queue: live_queue, started?: started?} = state
      ) do
    offset = context.pads[pad].options.offset
    new_live_queue = LiveQueue.add_queue(live_queue, pad_id, offset)

    {actions, started?} =
      if started? or is_nil(state.latency),
        do: {[], started?},
        else: {[start_timer: {:initiator, state.latency}], true}

    {actions, %{state | live_queue: new_live_queue, started?: started?}}
  end

  @impl true
  def handle_buffer(
        Pad.ref(:input, pad_id),
        buffer,
        _context,
        %{live_queue: live_queue} = state
      ) do
    new_live_queue = LiveQueue.add_buffer(live_queue, pad_id, buffer)

    {[], %{state | live_queue: new_live_queue}}
  end

  @impl true
  def handle_end_of_stream(
        Pad.ref(:input, pad_id),
        context,
        %{eos_scheduled: true, live_queue: live_queue} = state
      ) do
    lq = LiveQueue.remove_queue(live_queue, pad_id)
    eos? = all_streams_ended?(context)
    state = %{state | live_queue: lq, end_of_stream?: eos?}
    {[], state}
  end

  def handle_end_of_stream(Pad.ref(:input, pad_id), _context, %{live_queue: live_queue} = state),
    do: {[], %{state | live_queue: LiveQueue.remove_queue(live_queue, pad_id)}}

  @impl true
  def handle_tick(:initiator, _context, state) do
    {[stop_timer: :initiator, start_timer: {:timer, @interval}], state}
  end

  def handle_tick(:timer, _context, %{end_of_stream?: end_of_stream?} = state) do
    {payload, state} = mix(@interval, state)

    {actions, payload, state} =
      if end_of_stream? and LiveQueue.all_queues_empty?(state.live_queue) do
        {flushed_payload, state} = flush_mixer(state)
        {[end_of_stream: :output, stop_timer: :timer], payload <> flushed_payload, state}
      else
        {[], payload, state}
      end

    if payload == <<>> do
      {actions, state}
    else
      {[buffer: {:output, %Buffer{payload: payload}}] ++ actions, state}
    end
  end

  @impl true
  def handle_parent_notification(
        :schedule_eos,
        context,
        %{started?: started?} = state
      ) do
    state = %{state | eos_scheduled: true}

    if all_streams_ended?(context) and started?,
      do: {[], %{state | end_of_stream?: true}},
      else: {[], state}
  end

  @impl true
  def handle_parent_notification({:start_mixing, _latency}, _context, %{started?: true} = state) do
    Membrane.Logger.warning("Live Audio Mixer has already started mixing.")
    {[], state}
  end

  @impl true
  def handle_parent_notification(
        {:start_mixing, _latency},
        _context,
        %{stream_format: nil} = state
      ) do
    Membrane.Logger.warning("Can't start mixing when `stream format` is nil")
    {[], state}
  end

  @impl true
  def handle_parent_notification({:start_mixing, latency}, _context, %{started?: false} = state),
    do: {[start_timer: {:initiator, latency}], %{state | latency: latency, started?: true}}

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

  defp mix(duration, %{live_queue: live_queue} = state) do
    {payloads, new_live_queue} = LiveQueue.get_audio(live_queue, duration)

    payloads =
      if payloads == [],
        do: [RawAudio.silence(state.stream_format, duration)],
        else: Enum.map(payloads, fn {_audio_id, payload} -> payload end)

    {payload, state} = mix_payloads(payloads, state)
    {payload, %{state | live_queue: new_live_queue}}
  end

  defp all_streams_ended?(%{pads: pads}) do
    pads
    |> Enum.filter(fn {pad_name, _info} -> pad_name != :output end)
    |> Enum.map(fn {_pad, %{end_of_stream?: end_of_stream?}} -> end_of_stream? end)
    |> Enum.all?()
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
