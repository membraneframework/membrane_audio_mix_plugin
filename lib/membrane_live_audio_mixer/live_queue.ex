defmodule Membrane.LiveAudioMixer.LiveQueue do
  @moduledoc """
  There are a lot of problems that the mixer can encounter while processing live audio streams:
  * packet loss resulting in small stream discontinuity
  * connection issues resulting in  complete lack of data
  * the need for enforcing max latency on the stream - packets that come too late have to be dropped

  The LiveQueue tackles all those problems.
  It has an independent queue for each stream.
  Every gap caused by late or dropped packets are filled with silence.
  If there is a need for more audio than there is in a queue, the missing part will also be filled with silence.
  """
  alias Membrane.RawAudio

  defmodule Queue do
    @moduledoc """
    The `Queue` module is responsible for storing a single live audio stream.
    """
    @type t :: %__MODULE__{
            buffer: binary(),
            buffer_duration: non_neg_integer(),
            offset: non_neg_integer(),
            draining?: boolean()
          }

    defstruct buffer: <<>>, buffer_duration: 0, offset: 0, draining?: false
  end

  @opaque t() :: %{
            queues: %{any() => Queue.t()},
            current_time: non_neg_integer(),
            stream_format: RawAudio.t()
          }

  @spec init(RawAudio.t()) :: t()
  def init(stream_format),
    do: %{queues: %{}, current_time: 0, stream_format: stream_format}

  @spec add_queue(t(), any(), non_neg_integer()) :: t()
  def add_queue(lq, id, offset \\ 0)

  def add_queue(lq, id, offset) when offset >= 0 do
    if get_in(lq, [:queues, id]) != nil, do: raise("Queue with id: '#{id}' already exists.")

    queue = %Queue{offset: offset}
    put_in(lq, [:queues, id], queue)
  end

  @doc """
  Removes queue from a live queue.

  If the queue is empty, it will be removed right away.
  Otherwise, it will be marked as `draining` and will be removed when it will get empty.
  """
  @spec remove_queue(t(), any()) :: t()
  def remove_queue(lq, id) do
    if not Map.has_key?(lq.queues, id), do: raise("Queue with id: '#{id}' doesn't exists")

    queue = lq.queues[id]

    cond do
      queue.draining? ->
        raise "Queue with id: '#{id}' is already marked as draining"

      queue.buffer_duration == 0 ->
        {_queue, lq} = pop_in(lq, [:queues, id])
        lq

      true ->
        update_in(lq, [:queues, id], &Map.put(&1, :draining?, true))
    end
  end

  @spec all_queues_empty?(t()) :: boolean
  def all_queues_empty?(%{queues: queues}),
    do:
      Enum.all?(queues, fn
        {_key, %{buffer_duration: 0}} -> true
        {_key, _queue} -> false
      end)

  @spec get_audio(t(), pos_integer()) :: {[{any(), binary()}], t()}
  def get_audio(%{current_time: current_time} = lq, duration) do
    {audios, new_lq} =
      Enum.map_reduce(lq.queues, lq, fn {id, queue}, acc_lq ->
        {audio, new_queue} = get_duration(lq, queue, duration)
        new_lq = put_in(acc_lq, [:queues, id], new_queue)
        {{id, audio}, new_lq}
      end)

    new_queues =
      new_lq.queues
      |> Enum.filter(fn
        {_key, %{draining?: true, buffer_duration: 0}} -> false
        _queue -> true
      end)
      |> Map.new()

    {audios, %{new_lq | queues: new_queues, current_time: current_time + duration}}
  end

  @doc """
  Adds to a specific queue.

  When a buffer is too old it will be dropped
  When a part of a buffer is too old, only the part that is "fresh" will be added.
  When a whole buffer is "fresh", the whole buffer will be added.
  All the wholes between audio packets will be filled with silence.

  The state of the buffer, whether it's too old or not, is based on LiveQueue's `current_time`.
  """
  @spec add_buffer(t(), any(), Membrane.Buffer.t()) :: t()
  def add_buffer(
        %{
          stream_format: stream_format,
          current_time: current_time,
          queues: queues
        } = lq,
        id,
        %{pts: pts, payload: payload}
      ) do
    queue = Map.fetch!(queues, id)
    pts = pts + queue.offset
    payload_duration = RawAudio.bytes_to_time(byte_size(payload), stream_format)
    end_pts = pts + payload_duration
    queue_ts = current_time + queue.buffer_duration

    case {pts > queue_ts, end_pts > queue_ts} do
      {false, true} ->
        drop_duration = queue_ts - pts
        drop_bytes = RawAudio.time_to_bytes(drop_duration, stream_format)
        <<_rest::binary-size(drop_bytes), to_add::binary>> = payload

        to_add_duration = payload_duration - drop_duration

        update_in(lq, [:queues, id], fn queue ->
          queue
          |> Map.update!(:buffer, &(&1 <> to_add))
          |> Map.update!(:buffer_duration, &(&1 + to_add_duration))
        end)

      {true, true} ->
        silence_duration = pts - queue_ts
        silence = RawAudio.silence(stream_format, silence_duration)

        new_lq =
          update_in(lq, [:queues, id], fn queue ->
            queue
            |> Map.update!(:buffer, &(&1 <> silence <> payload))
            |> Map.update!(:buffer_duration, &(&1 + silence_duration + payload_duration))
          end)

        new_lq

      _else ->
        lq
    end
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
