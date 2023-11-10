defmodule Membrane.AudioMixer.Support.RawAudioParser do
  @moduledoc """
  This element is responsible for adding timestamps to buffers.
  """

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}

  def_options stream_format: [
                spec: RawAudio.t() | nil,
                default: nil
              ]

  def_input_pad :input,
    flow_control: :auto,
    accepted_format:
      any_of(
        %RawAudio{sample_format: sample_format}
        when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be],
        Membrane.RemoteStream
      ),
    availability: :always

  def_output_pad :output,
    flow_control: :auto,
    availability: :always,
    accepted_format: RawAudio

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:current_time, 0)

    {[], state}
  end

  @impl true
  def handle_stream_format(
        _pad,
        stream_format,
        _context,
        %{stream_format: nil} = state
      ),
      do: {[stream_format: {:output, stream_format}], %{state | stream_format: stream_format}}

  @impl true
  def handle_stream_format(
        _pad,
        _stream_format,
        _context,
        %{stream_format: stream_format} = state
      ),
      do: {[stream_format: {:output, stream_format}], state}

  @impl true
  def handle_buffer(
        _pad,
        %{payload: payload},
        _context,
        %{
          current_time: current_time,
          stream_format: stream_format
        } = state
      ) do
    time = RawAudio.bytes_to_time(byte_size(payload), stream_format)
    action = [buffer: {:output, %Buffer{pts: current_time, payload: payload}}]

    {action, %{state | current_time: current_time + time}}
  end
end
