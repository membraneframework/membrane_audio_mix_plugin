defmodule Membrane.AudioMixer.LiveQueue do
  @moduledoc """
  """
  alias Membrane.AudioMixer.LiveQueue.Membrane.AudioMixer.LiveQueue.Queue
  alias Membrane.RawAudio

  defmodule Membrane.AudioMixer.LiveQueue.Queue do
    @type t :: %__MODULE__{
            buffer: binary(),
            buffer_duration: non_neg_integer(),
            offset: non_neg_integer(),
            finished?: boolean()
          }

    defstruct buffer: <<>>, buffer_duration: 0, offset: 0, finished?: false
  end

  @opaque state_t() :: %{
            queues: %{any() => Queue.t()},
            current_time: non_neg_integer(),
            stream_format: RawAudio.t()
          }

  @spec init(RawAudio.t()) :: state_t()
  def init(stream_format),
    do: %{queues: %{}, current_time: 0, stream_format: stream_format}

  @spec add_queue(state_t(), any(), non_neg_integer()) :: {:ok, state_t()}
  def add_queue(state, id, offset \\ 0) do
    queue = %Queue{offset: offset}
    state = put_in(state, [:queues, id], queue)
    {:ok, state}
  end

  @spec remove_queue(state_t(), any()) :: {:ok, state_t()}
  def remove_queue(state, id) do
    state =
      if state.queues[id].buffer.duration == 0 do
        {_queue, state} = pop_in(state, [:queues, id])
        state
      else
        put_in(state, [:queues, id, :finished?], true)
      end

    {:ok, state}
  end

  @spec add_buffer(state_t(), any(), Membrane.Buffer.t()) ::
          {:ok, state_t()} | {:error, state_t()}
  def add_buffer(
        %{
          stream_format: stream_format,
          current_time: current_time,
          queues: queues
        } = state,
        id,
        %{pts: pts, payload: payload}
      ) do
    queue = queues[id]
    pts = pts + queue.offset
    payload_duration = RawAudio.bytes_to_time(byte_size(payload), stream_format)
    end_pts = pts + payload_duration
    queue_ts = current_time + queue.buffer_duration

    case {pts > queue_ts, end_pts > queue_ts} do
      {false, false} ->
        {:ok, state}

      {false, true} ->
        drop_duration = queue_ts - pts
        drop_bytes = RawAudio.time_to_bytes(drop_duration, stream_format)
        <<_rest::binary-size(drop_bytes), to_add::binary>> = payload

        to_add_duration = payload_duration - drop_duration

        new_state =
          update_in(state, [:queues, id], fn queue ->
            queue
            |> Map.update!(:buffer, &(&1 <> to_add))
            |> Map.update!(:buffer_duration, &(&1 + to_add_duration))
          end)

        {:ok, new_state}

      {true, true} ->
        silence_duration = pts - queue_ts
        silence = RawAudio.silence(stream_format, silence_duration)

        new_state =
          update_in(state, [:queues, id], fn queue ->
            queue
            |> Map.update!(:buffer, &(&1 <> silence <> payload))
            |> Map.update!(:buffer_duration, &(&1 + silence_duration + payload_duration))
          end)

        {:ok, new_state}

      _else ->
        {:error, state}
    end
  end

  @spec get_audio(state_t(), pos_integer()) :: {[{any(), binary()}], state_t()}
  def get_audio(%{current_time: current_time} = state, duration) do
    {audios, new_state} =
      Enum.map_reduce(state.queues, state, fn {id, queue}, acc_state ->
        {audio, new_queue} = get_duration(state, queue, duration)
        new_state = put_in(acc_state, [:queues, id], new_queue)
        {{id, audio}, new_state}
      end)

    new_queues =
      new_state.queues
      |> Enum.filter(fn
        %{offset?: true, buffer_duration: 0} -> false
        _queue -> true
      end)
      |> Map.new()

    {audios, %{new_state | queues: new_queues, current_time: current_time + duration}}
  end

  defp get_duration(%{stream_format: stream_format}, queue, duration) do
    if queue.buffer_duration < duration do
      audio = queue.buffer <> RawAudio.silence(stream_format, duration - queue.buffer_duration)
      {audio, %{queue | buffer: <<>>, buffer_duration: 0}}
    else
      bytes = RawAudio.time_to_bytes(duration, stream_format)
      <<audio::binary-size(bytes), new_buffer::binary>> = queue.buffer
      {audio, %{queue | buffer: new_buffer, buffer_duration: queue.buffer_duration - duration}}
    end
  end
end
