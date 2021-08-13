defmodule Membrane.AudioInterleaver do
  @moduledoc """
  TODO remove "rem finished pads"
  -> then state not necessary to try_interleave?
  """

  use Membrane.Filter
  use Bunch

  alias Membrane.AudioMixer.DoInterleave
  alias Membrane.Buffer
  alias Membrane.Caps.Audio.Raw, as: Caps

  require Membrane.Logger

  def_options caps: [
                type: :struct,
                spec: Caps.t(),
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
                # TODO list?
                type: :list,
                spec: list(integer),
                description: """
                Order in which channels should be interleaved
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
    caps: Caps

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:pads, %{})
      |> Map.put(:channels, length(options.order))

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

  # todo here count channels, maybe default order? (sorted ids)

  @impl true
  def handle_prepared_to_playing(_context, %{caps: %Caps{} = caps} = state) do
    {{:ok, caps: {:output, caps}}, state}
  end

  def handle_prepared_to_playing(_context, %{caps: nil} = state) do
    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :bytes, _context, %{channels: channels} = state) do
    Membrane.Logger.debug("handle bytes2")
    do_handle_demand(div(size, channels), state)
  end

  # TODO
  @impl true
  def handle_demand(
        :output,
        buffers_count,
        :buffers,
        _context,
        %{frames_per_buffer: frames, caps: caps} = state
      ) do
    Membrane.Logger.debug("handle buffer")

    case caps do
      nil ->
        {:ok, state}

      _caps ->
        size = buffers_count * Caps.frames_to_bytes(frames, caps)

        do_handle_demand(size, state)
    end
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

    {_, {buffer, state}} = try_interleave(state)

    all_streams_ended =
      state.pads
      |> Enum.map(fn {_pad, %{stream_ended: stream_ended}} -> stream_ended end)
      |> Enum.all?()

    if all_streams_ended do
      {{:ok, buffer: buffer, end_of_stream: :output}, state}
    else
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
        %Buffer{payload: payload} = _buffer,
        _context,
        %{caps: caps, pads: pads} = state
      ) do
    sample_size = Caps.sample_size(caps)

    {size, pads} =
      Bunch.Access.get_and_update_in(
        pads,
        [pad, :queue],
        &{byte_size(&1 <> payload), &1 <> payload}
      )

    state = %{state | pads: pads}

    if size >= sample_size do
      case(try_interleave(state)) do
        {:ok, {buffer, state}} -> {{:ok, buffer: buffer}, state}
        {:empty, _} -> {:ok, state}
      end
    else
      Membrane.Logger.debug("redemand")
      {{:ok, redemand: :output}, state}
    end
  end

  @impl true
  def handle_caps(pad, caps, _context, state) do
    case state.caps do
      nil ->
        state = %{state | caps: caps}
        {{:ok, caps: {:output, caps}, redemand: :output}, state}

      ^caps ->
        {:ok, state}

      _invalid_caps ->
        raise(
          RuntimeError,
          "received invalid caps on pad #{inspect(pad)}, expected: #{inspect(state.caps)}, got: #{inspect(caps)}"
        )
    end
  end

  defp do_handle_demand(size, %{pads: pads} = state) do
    demands =
      Enum.map(
        pads,
        fn {pad, %{queue: queue}} ->
          demand_size =
            queue
            |> byte_size()
            |> then(&max(0, size - &1))

          {:demand, {pad, demand_size}}
        end
      )

    {{:ok, demands}, state}
  end

  defp try_interleave(%{caps: caps, pads: pads} = state) do
    sample_size = Caps.sample_size(caps)

    min_length =
      min_queue_length(pads)
      |> trunc_to_whole_samples(sample_size)

    if min_length >= sample_size do
      {payload, pads} = DoInterleave.interleave(min_length, caps, pads, state.order)
      pads = remove_finished_pads(pads, sample_size)

      Membrane.Logger.debug("#{inspect(byte_size(payload))}")
      buffer = {:output, %Buffer{payload: payload}}
      {:ok, {buffer, %{state | pads: pads}}}
    else
      empty_buffer = {:output, %Buffer{payload: <<>>}}
      {:empty, {empty_buffer, state}}
    end
  end

  # Returns minimum number of bytes present in all queues
  defp min_queue_length(pads) do
    pads
    |> Enum.map(fn {_pad, %{queue: queue}} -> byte_size(queue) end)
    |> Enum.min(fn -> 0 end)
  end

  # Returns the biggest multiple of `sample_size` that is not bigger than `size`
  defp trunc_to_whole_samples(size, sample_size)
       when is_integer(size) and is_integer(sample_size) do
    rest = rem(size, sample_size)
    size - rest
  end

  defp remove_finished_pads(pads, sample_size) do
    pads
    |> Enum.flat_map(fn
      {_pad, %{queue: queue, stream_ended: true}} when byte_size(queue) < sample_size -> []
      pad_data -> [pad_data]
    end)
    |> Map.new()
  end
end
