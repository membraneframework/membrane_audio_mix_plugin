defmodule Membrane.AudioMixer.Support.NetworkSimulator do
  @moduledoc """
  This element is responsible for the simulation of real network communication.
  """

  use Membrane.Filter

  def_options drop_every_other_packet: [
                spec: boolean(),
                description: """
                If set to true, every other packet will be dropped.
                """,
                default: false
              ],
              latency: [
                spec: Membrane.Time.t() | nil,
                description: """
                If value is different than `nil`, every packet will randomize a delay from 0 to `latency`.
                """,
                default: nil
              ]

  def_input_pad :input,
    demand_mode: :auto,
    accepted_format:
      any_of(
        %Membrane.RawAudio{sample_format: sample_format}
        when sample_format in [:s8, :s16le, :s16be, :s24le, :s24be, :s32le, :s32be]
      ),
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    availability: :always,
    accepted_format: Membrane.RawAudio

  @impl true
  def handle_init(_ctx, options) do
    state =
      options
      |> Map.from_struct()
      |> Map.put(:counter, 0)

    {[], state}
  end

  @impl true
  def handle_process(
        _pad,
        buffer,
        _context,
        %{
          drop_every_other_packet: drop?,
          counter: counter,
          latency: latency
        } = state
      ) do
    action = [buffer: {:output, buffer}]
    state = %{state | counter: counter + 1}

    case {latency, drop?, rem(counter, 2) == 0} do
      {_latency, true, true} ->
        {[], state}

      {nil, _drop?, _even?} ->
        {action, state}

      _else ->
        buffer_latency =
          latency
          |> :rand.uniform()
          |> Membrane.Time.as_milliseconds()
          |> Ratio.floor()

        Process.send_after(self(), %{action: action}, buffer_latency)
        {[], state}
    end
  end

  @impl true
  def handle_end_of_stream(_pad, _context, %{latency: nil} = state),
    do: {[end_of_stream: :output], state}

  @impl true
  def handle_end_of_stream(_pad, _context, %{latency: latency} = state) do
    latency =
      latency
      |> Membrane.Time.as_milliseconds()
      |> Ratio.floor()

    Process.send_after(self(), %{action: [end_of_stream: :output]}, latency)
    {[], state}
  end

  @impl true
  def handle_info(%{action: action}, _context, state) do
    {action, state}
  end
end
