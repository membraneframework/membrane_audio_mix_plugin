defmodule Membrane.AudioMixer do
  @moduledoc """
  This element performs audio mixing.

  Audio format can be set as an element option or received through caps from input pads. All
  received caps have to be identical and match ones in element option (if that option is
  different than nil).

  Input pads can have offset - it tells how much silence should be added before first sample
  from that pad. Offset have to be positive.

  Mixer mixes only raw audio (PCM), so some parser may be needed to precede it in pipeline.
  """

  use Membrane.Filter
  use Bunch
  use Membrane.Log, tags: :membrane_audio_mixer

  alias Membrane.AudioMixer.DoMix
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Time

  def_options caps: [
                type: :struct,
                spec: Caps.t(),
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                """,
                default: nil
              ]

  def_output_pad :output,
    mode: :pull,
    availability: :always,
    caps: Caps

  def_input_pad :input,
    mode: :pull,
    availability: :on_request,
    demand_unit: :bytes,
    caps: Caps,
    options: [
      offset: [
        spec: Time.t(),
        default: 0,
        description: "Offset of the input audio at the pad."
      ]
    ]

  @impl true
  def handle_init(%__MODULE__{caps: caps}) do
    state = %{
      caps: caps,
      pads: %{}
    }

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
  def handle_demand(:output, size, :bytes, _context, %{pads: pads} = state) do
    demands =
      pads
      |> Enum.map(fn {pad, %{queue: queue}} ->
        demand_size =
          queue
          |> byte_size()
          |> then(fn s -> max(0, size - s) end)

        {:demand, {pad, demand_size}}
      end)

    {{:ok, demands}, state}
  end

  @impl true
  def handle_start_of_stream(pad, context, state) do
    info("mixer start of stream #{inspect(pad)}")

    offset = context.pads[pad].options.offset
    silence = Caps.sound_of_silence(state.caps, offset)

    state =
      Bunch.Access.update_in(
        state,
        [:pads, pad],
        &%{&1 | queue: silence}
      )

    demand = get_default_demand(state)

    {{:ok, demand: {pad, demand}}, state}
  end

  @impl true
  def handle_end_of_stream(pad, _context, state) do
    info("mixer end of stream #{inspect(pad)}")

    state =
      Bunch.Access.update_in(
        state,
        [:pads, pad],
        &%{&1 | stream_ended: true}
      )

    {:ok, state}
  end

  @impl true
  def handle_event(_pad, _event, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(pad, buffer, _context, state) do
    %Buffer{payload: payload} = buffer
    %{caps: caps, pads: pads} = state

    time_frame = Caps.frame_size(caps)

    {size, pads} =
      Bunch.Access.get_and_update_in(
        pads,
        [pad, :queue],
        &{byte_size(&1), &1 <> payload}
      )

    if size >= time_frame do
      do_handle_process(caps, %{state | pads: pads})
    else
      {{:ok, redemand: :output}, %{state | pads: pads}}
    end
  end

  @impl true
  def handle_caps(:input, caps, _context, state) do
    cond do
      state.caps == nil ->
        state = %{state | caps: caps}
        {{:ok, caps: {:output, caps}}, state}

      state.caps == caps ->
        {:ok, state}

      true ->
        raise(
          RuntimeError,
          "incompatible audio formats: they should be identical on all pads and match caps provided as element option"
        )
    end
  end

  defp get_default_demand(%{caps: caps} = _state) do
    Caps.time_to_bytes(500, caps)
  end

  defp do_handle_process(caps, state) do
    %{pads: pads} = state

    time_frame = Caps.frame_size(caps)
    mix_size = mix_size(pads, time_frame)

    if mix_size >= time_frame do
      {payload, pads} = mix(pads, mix_size, caps)
      pads = remove_finished_pads(pads, time_frame)

      buffer = {:output, %Buffer{payload: payload}}
      state = %{state | pads: pads}

      {{:ok, buffer: buffer}, state}
    else
      {:ok, state}
    end
  end

  defp mix_size(pads, time_frame) do
    fallback = fn ->
      pads
      |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
      |> Enum.max()
    end

    pads
    |> Enum.flat_map(fn
      {_pad, %{queue: queue, stream_ended: false}} -> [byte_size(queue)]
      _ -> []
    end)
    |> Enum.min(fallback)
    |> int_part(time_frame)
  end

  # Returns the biggest multiple of `divisor` that is not bigger than `number`
  defp int_part(number, divisor) when is_integer(number) and is_integer(divisor) do
    rest = rem(number, divisor)
    number - rest
  end

  defp mix(pads, mix_size, _caps) when map_size(pads) == 1 do
    {pad, data} =
      pads
      |> Map.to_list()
      |> hd()

    <<payload::binary-size(mix_size), queue::binary>> = data.queue

    {payload, %{pad => %{data | queue: queue}}}
  end

  defp mix(pads, mix_size, caps) do
    {payloads, pads} =
      pads
      |> Enum.map(fn
        {pad, %{queue: <<payload::binary-size(mix_size), queue::binary>>} = data} ->
          {payload, {pad, %{data | queue: queue}}}

        {pad, %{queue: payload} = data} ->
          {payload, {pad, %{data | queue: <<>>}}}
      end)
      |> Enum.unzip()

    payload = DoMix.mix(payloads, caps)
    pads = Map.new(pads)
    {payload, pads}
  end

  defp remove_finished_pads(pads, time_frame) do
    pads
    |> Enum.flat_map(fn
      {_pad, %{queue: queue, stream_ended: true}} when byte_size(queue) < time_frame -> []
      pad_data -> [pad_data]
    end)
    |> Map.new()
  end
end
