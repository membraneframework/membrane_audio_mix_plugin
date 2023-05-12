defmodule Membrane.LiveAudioMixer do
  @moduledoc """
  This element performs audio mixing for live streams.

  Audio format can be set as an element option or received through stream_format from input pads. All
  received stream_format have to be identical and match ones in element option (if that option is
  different from `nil`).

  Input pads can have offset - it tells how much timestamps differ from mixer time.

  Mixer mixes only raw audio (PCM), so some parser may be needed to precede it in pipeline.
  """

  use Membrane.Filter
  use Bunch

  require Membrane.Logger

  alias Membrane.AudioMixer.{Adder, ClipPreventingAdder, LiveQueue, NativeAdder}
  alias Membrane.Buffer
  alias Membrane.RawAudio
  alias Membrane.Time

  @interval Membrane.Time.milliseconds(20)

  def_options stream_format: [
                spec: RawAudio.t(),
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                """,
                default: nil
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
              latency: [
                spec: non_neg_integer(),
                description: """
                The value determines after what time the clock will start interval that mixes audio in real time.
                Latency is crucial to quality of output audio, the smaller the value, the more packets will be lost.
                But the biggest the value, the latency of the stream is bigger.
                """,
                default: Membrane.Time.milliseconds(200),
                inspector: &Time.inspect/1
              ]

  def_output_pad :output,
    demand_mode: :auto,
    availability: :always,
    accepted_format: RawAudio

  def_input_pad :input,
    demand_mode: :auto,
    availability: :on_request,
    accepted_format:
      any_of(
        %RawAudio{sample_format: sample_format}
        when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be]
      ),
    options: [
      offset: [
        spec: Time.non_neg_t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(_ctx, %__MODULE__{stream_format: stream_format} = options) do
    if options.native_mixer && !options.prevent_clipping do
      raise("Invalid element options, for native mixer only clipping preventing one is available")
    else
      live_queue =
        if stream_format == nil,
          do: nil,
          else: LiveQueue.init(stream_format)

      state =
        options
        |> Map.from_struct()
        |> Map.put(:mixer_state, initialize_mixer_state(stream_format, options))
        |> Map.put(:live_queue, live_queue)
        |> Map.put(:end_of_stream?, false)

      {[], state}
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
        %{live_queue: live_queue} = state
      ) do
    offset = context.pads[pad].options.offset

    new_live_queue = LiveQueue.add_queue(live_queue, pad_id, offset)

    started_input_pads_number =
      context.pads
      |> Enum.filter(fn {_id, pad} -> pad.direction == :input and pad.start_of_stream? == true end)
      |> Enum.count()

    actions =
      if started_input_pads_number == 1,
        do: [start_timer: {:initiator, state.latency}],
        else: []

    {actions, %{state | live_queue: new_live_queue}}
  end

  @impl true
  def handle_process(
        Pad.ref(:input, pad_id),
        buffer,
        _context,
        %{live_queue: live_queue} = state
      ) do
    new_live_queue = LiveQueue.add_buffer(live_queue, pad_id, buffer)

    {[], %{state | live_queue: new_live_queue}}
  end

  @impl true
  def handle_end_of_stream(Pad.ref(:input, pad_id), context, %{live_queue: live_queue} = state) do
    new_live_queue = LiveQueue.remove_queue(live_queue, pad_id)

    {actions, end_of_stream?, state} =
      cond do
        !all_streams_ended?(context) ->
          {[], false, state}

        LiveQueue.all_queues_empty?(new_live_queue) ->
          {payload, state} = flush_mixer(state)

          {[
             buffer: {:output, %Buffer{payload: payload}},
             end_of_stream: :output,
             stop_timer: :timer
           ], true, state}

        true ->
          {[], true, state}
      end

    {actions, %{state | live_queue: new_live_queue, end_of_stream?: end_of_stream?}}
  end

  @impl true
  def handle_tick(:initiator, _context, state) do
    {[stop_timer: :initiator, start_timer: {:timer, @interval}], state}
  end

  def handle_tick(:timer, _context, %{end_of_stream?: end_of_stream?} = state) do
    {payload, state} = mix(20 |> Membrane.Time.milliseconds(), state)

    {actions, payload, state} =
      if end_of_stream? and LiveQueue.all_queues_empty?(state.live_queue) do
        {flushed_payload, state} = flush_mixer(state)
        {[end_of_stream: :output, stop_timer: :timer], payload <> flushed_payload, state}
      else
        {[], payload, state}
      end

    {[buffer: {:output, %Buffer{payload: payload}}] ++ actions, state}
  end

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
    payloads = Enum.map(payloads, fn {_audio_id, payload} -> payload end)
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
