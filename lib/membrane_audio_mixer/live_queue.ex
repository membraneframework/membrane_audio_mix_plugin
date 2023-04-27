defmodule Membrane.AudioMixer.LiveQueue do
  @moduledoc """
  """
  alias Membrane.RawAudio

  def init(stream_format),
    do: {:ok, %{queues: %{}, offsets: %{}, current_time: 0, stream_format: stream_format}}

  def add_queue(audio_id, offset \\ 0, %{queues: queues, offsets: offsets} = state) do
    queues = Map.put(queues, audio_id, <<>>)
    offsets = Map.put(offsets, audio_id, offset)
    {:ok, %{state | queues: queues, offsets: offsets}}
  end

  def remove_queue(audio_id, state) do
    queues = state.queues
    queues = Map.delete(queues, audio_id)
    {:ok, %{state | queues: queues}}
  end

  def add_buffer(
        audio_id,
        %{pts: pts, payload: payload},
        %{
          stream_format: stream_format,
          current_time: current_time,
          offsets: offsets,
          queues: queues
        } = state
      ) do
    pts = pts + Map.get(offsets, audio_id)

    current_time =
      current_time + RawAudio.bytes_to_time(byte_size(Map.get(queues, audio_id)), stream_format)

    end_pts = pts + RawAudio.bytes_to_time(byte_size(payload), stream_format)

    case {pts > current_time, end_pts > current_time} do
      {false, false} ->
        {:ok, state}

      {false, true} ->
        duration = end_pts - current_time
        bytes = RawAudio.time_to_bytes(duration, stream_format)
        <<to_add::binary-size(bytes), _rest::binary>> = payload
        new_state = update_in(state, [:queues, audio_id], fn queue -> queue <> to_add end)
        {:ok, new_state}

      {true, true} ->
        silence_duration = pts - current_time
        silence = RawAudio.silence(stream_format, silence_duration)

        new_state =
          update_in(state, [:queues, audio_id], fn queue -> queue <> silence <> payload end)

        {:ok, new_state}

      _else ->
        {:error, state}
    end
  end

  def get_audio(duration, %{current_time: current_time} = state) do
    {audios, new_state} =
      Enum.map_reduce(state.queues, state, fn {audio_id, _queue}, acc_state ->
        {audio, new_state} = get_audio(audio_id, duration, acc_state)
        {{audio_id, audio}, new_state}
      end)

    {audios, %{new_state | current_time: current_time + duration}}
  end

  defp get_audio(audio_id, duration, state) do
    queue = get_in(state, [:queues, audio_id])
    {audio, new_queue} = get_duration(queue, duration, state)
    new_state = put_in(state, [:queues, audio_id], new_queue)
    {audio, new_state}
  end

  defp get_duration(queue, duration, %{stream_format: stream_format}) do
    queue_duration = RawAudio.bytes_to_time(byte_size(queue), stream_format)

    if queue_duration < duration do
      audio = queue <> RawAudio.silence(stream_format, duration - queue_duration)
      {audio, <<>>}
    else
      bytes = RawAudio.time_to_bytes(duration, stream_format)
      <<audio::binary-size(bytes), new_queue::binary>> = queue
      {audio, new_queue}
    end
  end
end
