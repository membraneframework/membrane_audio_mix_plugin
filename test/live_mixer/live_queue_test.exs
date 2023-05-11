defmodule Membrane.LiveAudioMixer.LiveQueueTest do
  use ExUnit.Case, async: true

  alias Membrane.AudioMixer.LiveQueue
  alias Membrane.{Buffer, RawAudio, Time}

  @stream_format %RawAudio{
    channels: 1,
    sample_rate: 48_000,
    sample_format: :s16le
  }

  @fifty_ms Time.milliseconds(50)
  @hundred_ms Time.milliseconds(100)
  @silence_50 RawAudio.silence(@stream_format, @fifty_ms)
  @silence_100 RawAudio.silence(@stream_format, @hundred_ms)
  @sound_50 String.duplicate(<<1>>, div(byte_size(@silence_100), 2))
  @sound_100 String.duplicate(<<1>>, byte_size(@silence_100))

  setup do
    live_queue = LiveQueue.init(@stream_format)

    %{live_queue: live_queue}
  end

  describe "Queues" do
    test "adding", %{live_queue: live_queue} do
      live_queue = LiveQueue.add_queue(live_queue, 1)
      {audios, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert [{1, @silence_100}] == audios

      live_queue = LiveQueue.add_queue(live_queue, 2)
      {audios, _live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert [{1, @silence_100}, {2, @silence_100}] == audios
    end

    test "removing", %{live_queue: live_queue} do
      live_queue = LiveQueue.add_queue(live_queue, 1)
      live_queue = LiveQueue.add_queue(live_queue, 2)

      # remove empty queue - should be removed instantly from state
      live_queue = LiveQueue.remove_queue(live_queue, 1)
      {audios, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert [{2, @silence_100}] = audios

      live_queue =
        LiveQueue.add_buffer(live_queue, 2, %Buffer{pts: @hundred_ms, payload: @silence_100})

      # remove not empty queue - should be marked as finished and removed when it gets empty
      live_queue = LiveQueue.remove_queue(live_queue, 2)
      {audios, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert [{2, @silence_100}] == audios

      # queue with id: 2 should be removed because it got empty inside `get_audio` call
      {audios, _live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert [] == audios
    end

    test "checking if queues are empty", %{live_queue: live_queue} do
      assert LiveQueue.all_queues_empty?(live_queue)

      live_queue = LiveQueue.add_queue(live_queue, 1)
      assert LiveQueue.all_queues_empty?(live_queue)

      live_queue = LiveQueue.add_buffer(live_queue, 1, %Buffer{pts: 0, payload: @silence_100})
      assert !LiveQueue.all_queues_empty?(live_queue)

      {_audio, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
      assert LiveQueue.all_queues_empty?(live_queue)
    end
  end

  test "adding", %{live_queue: live_queue} do
    live_queue = LiveQueue.add_queue(live_queue, 1)
    live_queue = LiveQueue.add_buffer(live_queue, 1, %Buffer{pts: 0, payload: @sound_100})

    {audios, live_queue} = LiveQueue.get_audio(live_queue, 2 * @hundred_ms)
    audio = @sound_100 <> @silence_100
    assert [{1, audio}] == audios

    # Add buffer that is to old, should not change anything
    live_queue = LiveQueue.add_buffer(live_queue, 1, %Buffer{pts: 0, payload: @sound_100})
    {audios, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
    assert [{1, @silence_100}] == audios

    # Add buffer that has half of the payload to old to use, should add only half of the buffer (50ms)
    buffer_pts = 2 * @hundred_ms + @fifty_ms

    live_queue =
      LiveQueue.add_buffer(live_queue, 1, %Buffer{payload: @sound_100, pts: buffer_pts})

    {audios, live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
    audio = @sound_50 <> @silence_50
    assert [{1, audio}] == audios

    # Add buffer that is ahead of queue payload by 50 ms, should add 50 ms of silence than whole buffer payload
    buffer_pts = Time.milliseconds(500)

    live_queue =
      LiveQueue.add_buffer(live_queue, 1, %Buffer{payload: @sound_100, pts: buffer_pts})

    {audios, live_queue} = LiveQueue.get_audio(live_queue, 2 * @hundred_ms)
    audio = @silence_100 <> @sound_100
    assert [{1, audio}] == audios

    # Add second queue
    live_queue = LiveQueue.add_queue(live_queue, 2, 6 * @hundred_ms)
    live_queue = LiveQueue.add_buffer(live_queue, 2, %Buffer{pts: 0, payload: @sound_100})
    {audios, _live_queue} = LiveQueue.get_audio(live_queue, @hundred_ms)
    assert [{1, @silence_100}, {2, @sound_100}] == audios
  end
end
