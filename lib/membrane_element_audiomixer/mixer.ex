defmodule Membrane.Element.AudioMixer.Mixer do
  use Membrane.Filter
  use Bunch

  alias Membrane.Element.AudioMixer.DoMix
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Time
  use Membrane.Log, tags: :membrane_element_audiomixer

  def_options caps: [
                type: :struct,
                spec: Caps.t(),
                description: """
                The value defines a raw audio format of pads connected to the
                element. It should be the same for all the pads.
                """
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
      inputs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_pad_added(_pad, _context, state) do
    {:ok, state}
  end

  @impl true
  def handle_pad_removed(pad, _context, state) do
    state = Bunch.Access.delete_in(state, [:inputs, pad])

    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _context, %{inputs: inputs} = state) do
    demands =
      inputs
      |> Enum.map(fn {input, %{queue: queue}} ->
        demand_size =
          queue
          |> byte_size()
          |> then(fn s -> max(0, size - s) end)

        {:demand, {input, demand_size}}
      end)

    {{:ok, demands}, state}
  end

  @impl true
  def handle_start_of_stream(pad, _context, state) do
    info("mixer start of stream #{inspect(pad)}")

    demand = get_default_demand(state)

    state =
      Bunch.Access.put_in(
        state,
        [:inputs, pad],
        %{queue: <<>>, eos: false}
      )

    {{:ok, demand: {pad, demand}}, state}
  end

  @impl true
  def handle_end_of_stream(pad, _context, state) do
    info("mixer end of stream #{inspect(pad)}")

    state =
      Bunch.Access.update_in(
        state,
        [:inputs, pad],
        &%{&1 | eos: true}
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
    %{caps: caps, inputs: inputs} = state

    time_frame = Caps.frame_size(caps)

    {size, inputs} =
      Bunch.Access.get_and_update_in(
        inputs,
        [pad, :queue],
        &{byte_size(&1), &1 <> payload}
      )

    if size >= time_frame do
      do_handle_process(caps, %{state | inputs: inputs})
    else
      {{:ok, redemand: :output}, %{state | inputs: inputs}}
    end
  end

  @impl true
  def handle_caps(:input, _caps, _context, state) do
    caps = %Caps{
      channels: 1,
      format: :s16le,
      sample_rate: 16_000
    }

    {{:ok, caps: {:output, caps}}, state}
  end

  defp get_default_demand(%{caps: caps} = _state) do
    Caps.time_to_bytes(500, caps)
  end

  defp do_handle_process(caps, state) do
    %{inputs: inputs} = state

    time_frame = Caps.frame_size(caps)
    mix_size = mix_size(inputs, time_frame)

    if mix_size >= time_frame do
      {payload, inputs} = mix(inputs, mix_size, caps)
      inputs = remove_finished_inputs(inputs, time_frame)

      buffer = {:output, %Buffer{payload: payload}}
      state = %{state | inputs: inputs}

      {{:ok, buffer: buffer}, state}
    else
      {:ok, state}
    end
  end

  defp mix_size(inputs, time_frame) do
    fallback = fn ->
      inputs
      |> Enum.map(fn {_input, %{queue: queue}} -> byte_size(queue) end)
      |> Enum.max()
    end

    inputs
    |> Enum.flat_map(fn
      {_input, %{queue: queue, eos: false}} -> [byte_size(queue)]
      _ -> []
    end)
    |> Enum.min(fallback)
    |> int_part(time_frame)
  end

  # returns the biggest multiple of `divisor` that is not bigger than `number`
  defp int_part(number, divisor) when is_integer(number) and is_integer(divisor) do
    rest = rem(number, divisor)
    number - rest
  end

  defp mix(inputs, mix_size, _caps) when map_size(inputs) == 1 do
    {input, data} =
      inputs
      |> Map.to_list()
      |> hd()

    <<payload::binary-size(mix_size), queue::binary>> = data.queue

    {payload, %{input => %{data | queue: queue}}}
  end

  defp mix(inputs, mix_size, caps) do
    {payloads, inputs} =
      inputs
      |> Enum.map(fn
        {input, %{queue: <<payload::binary-size(mix_size), queue::binary>>} = data} ->
          {payload, {input, %{data | queue: queue}}}

        {input, %{queue: payload} = data} ->
          {payload, {input, %{data | queue: <<>>}}}
      end)
      |> Enum.unzip()

    payload = DoMix.mix(payloads, caps)
    inputs = Map.new(inputs)
    {payload, inputs}
  end

  defp remove_finished_inputs(inputs, time_frame) do
    inputs
    |> Enum.flat_map(fn
      {_input, %{queue: queue, eos: true}} when byte_size(queue) < time_frame -> []
      input_data -> [input_data]
    end)
    |> Map.new()
  end
end
