defmodule Membrane.LiveAudioMixer.LiveQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.AudioMixer.LiveQueue
  alias Membrane.AudioMixer.LiveQueue.Queue
  alias Membrane.{Buffer, RawAudio, Time}

  @stream_format %RawAudio{
    channels: 1,
    sample_rate: 48_000,
    sample_format: :s16le
  }
  @duration Time.milliseconds(100)
  @payload RawAudio.silence(@stream_format, @duration)
  @buffer %Buffer{pts: 0, payload: @payload}
  setup do
    live_queue = LiveQueue.init(@stream_format)

    %{live_queue: live_queue}
  end

  describe "Queues" do
    test "adding", %{live_queue: live_queue} do
      {:ok, %{queues: %{1 => queue}} = live_queue} = LiveQueue.add_queue(live_queue, 1)
      assert(queue == %Queue{})

      {:ok, %{queues: %{1 => _first_queue, 2 => second_queue}} = live_queue} =
        LiveQueue.add_queue(live_queue, 2, 1000)

      assert(second_queue == %Queue{offset: 1000})

      {:error, "Offset has to be a `non_neg_integer`"} = LiveQueue.add_queue(live_queue, 3, -1)
      {:error, "Queue with id: '2' already exists."} = LiveQueue.add_queue(live_queue, 2)
    end

    test "removing", %{live_queue: live_queue} do
      {:ok, live_queue} = LiveQueue.add_queue(live_queue, 1)
      {:ok, live_queue} = LiveQueue.add_queue(live_queue, 2)

      # remove empty queue - should be removed instantly from state
      {:ok, %{queues: queues} = live_queue} = LiveQueue.remove_queue(live_queue, 1)
      assert(queues == %{2 => %Queue{}})

      {:ok, live_queue} = LiveQueue.add_buffer(live_queue, 2, @buffer)

      # remove not empty queue - should be marked as finished and removed when it gets empty
      {:ok, %{queues: %{2 => %{finished?: true}}} = live_queue} =
        LiveQueue.remove_queue(live_queue, 2)

      {:error, "Queue with id: '2' is already marked as finished"} =
        LiveQueue.remove_queue(live_queue, 2)

      {:error, "Queue with id: '3' doesn't exists"} = LiveQueue.remove_queue(live_queue, 3)

      # queue with id: 2 should be removed because it gets empty inside `get_audio` call
      {_audios, %{queues: queues}} = LiveQueue.get_audio(live_queue, Time.milliseconds(100))

      assert(queues == %{})
    end
  end

  describe "Buffers" do
    test "adding", %{live_queue: live_queue} do
      {:ok, live_queue} = LiveQueue.add_queue(live_queue, 1)

      {:error, "Queue with id: unknown doesn't exist."} =
        LiveQueue.add_buffer(live_queue, :unknown, @buffer)

      {:ok, %{queues: %{1 => %Queue{buffer_duration: @duration, buffer: @payload}}}} =
        LiveQueue.add_buffer(live_queue, 1, @buffer)

      # Add buffer that is to old, should not change anything
      {:ok, %{queues: %{1 => %Queue{buffer_duration: @duration, buffer: @payload}}}} =
        LiveQueue.add_buffer(live_queue, 1, @buffer)

      duration = Time.milliseconds(200)
      silence = RawAudio.silence(@stream_format, duration)

      {:ok, %{queues: %{1 => %Queue{buffer_duration: ^duration, buffer: ^silence}}}} =
        LiveQueue.add_buffer(live_queue, 1, %Buffer{payload: @payload, pts: @duration})

      buffer_pts = Time.milliseconds(150)
      duration = Time.milliseconds(250)
      silence = RawAudio.silence(@stream_format, duration)

      # Add buffer that has half of the payload to old to use, should add only half of the buffer (50ms)
      {:ok, %{queues: %{1 => %Queue{buffer_duration: ^duration, buffer: ^silence}}}} =
        LiveQueue.add_buffer(live_queue, 1, %Buffer{payload: @payload, pts: buffer_pts})

      buffer_pts = Time.milliseconds(300)
      duration = Time.milliseconds(400)
      silence = RawAudio.silence(@stream_format, duration)

      # Add buffer that is ahead of queue payload by 50 ms, should add 50 ms of silence than whole buffer payload
      {:ok, %{queues: %{1 => %Queue{buffer_duration: ^duration, buffer: ^silence}}}} =
        LiveQueue.add_buffer(live_queue, 1, %Buffer{payload: @payload, pts: buffer_pts})
    end

    test "getting", %{live_queue: live_queue} do
      sound_100 = String.duplicate(<<1>>, byte_size(@payload))
      sound_50 = String.duplicate(<<1>>, div(byte_size(@payload), 2))

      current_time = duration = Time.milliseconds(50)

      {[], %{current_time: ^current_time} = live_queue} =
        LiveQueue.get_audio(live_queue, duration)

      {:ok, live_queue} = LiveQueue.add_queue(live_queue, 1)

      # Add buffer that has pts 50 ms behind `current_time`, should drop 50 ms from buffer's payload
      {:ok, %{queues: %{1 => %Queue{buffer_duration: ^duration, buffer: ^sound_50}}} = live_queue} =
        LiveQueue.add_buffer(live_queue, 1, %Buffer{pts: 0, payload: sound_100})

      current_time = Time.milliseconds(150)
      duration = Time.milliseconds(100)
      audio = sound_50 <> RawAudio.silence(@stream_format, Time.milliseconds(50))

      # Get 100 ms of audio from queue that has only 50 ms buffer, should get 50ms of buffer and add 50 ms of silence
      {[{1, ^audio}], %{current_time: ^current_time} = live_queue} =
        LiveQueue.get_audio(live_queue, duration)

      duration = Time.milliseconds(100)

      {:ok, live_queue} = LiveQueue.add_queue(live_queue, 2, current_time)

      {:ok,
       %{queues: %{1 => %Queue{buffer_duration: ^duration, buffer: ^sound_100}}} = live_queue} =
        LiveQueue.add_buffer(live_queue, 1, %Buffer{
          pts: current_time,
          payload: sound_100
        })

      {:ok, %{queues: %{2 => %Queue{buffer: ^sound_100, buffer_duration: duration}}} = live_queue} =
        LiveQueue.add_buffer(live_queue, 2, %Buffer{payload: sound_100, pts: 0})

      current_time = Time.milliseconds(250)

      # Get 100 ms of audio from two queues that have exactly that amount, should return two tuples with 100 ms of sound
      {[{1, ^sound_100}, {2, ^sound_100}],
       %{
         current_time: ^current_time,
         queues: %{1 => %Queue{buffer: <<>>}, 2 => %Queue{buffer: <<>>}}
       }} = LiveQueue.get_audio(live_queue, duration)
    end
  end
end
