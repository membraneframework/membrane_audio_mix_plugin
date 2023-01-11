defmodule Membrane.AudioMixer.ClipPreventingAdder do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). The result is a single track in the format mixed tracks are encoded in.
  If overflow happens during mixing, a wave will be scaled down to the max sample value.

  Description of the algorithm:
    - Start with an empty queue
    - Enqueue merged values while the sign of the values remains the same
    - If the sign of values changes or adder is flushed:
      - If none of the values overflows limits of the format, convert the queued values
        to binary samples and return them
      - Otherwise, scale down the queued values, so the peak of the wave will become
        maximal (minimal) allowed value, then convert it to binary samples and return
        them.
  """

  @behaviour Membrane.AudioMixer.Mixer

  alias Membrane.AudioMixer.Helpers
  alias Membrane.RawAudio

  @enforce_keys [:stream_format, :sample_size]
  defstruct @enforce_keys ++ [is_wave_positive: true, queue: []]

  @type t :: %__MODULE__{
          stream_format: RawAudio.t(),
          is_wave_positive: boolean(),
          sample_size: integer(),
          queue: [integer()]
        }

  @impl true
  def init(stream_format) do
    size = RawAudio.sample_size(stream_format)

    %__MODULE__{stream_format: stream_format, sample_size: size}
  end

  @impl true
  def mix(buffers, %__MODULE__{stream_format: stream_format, sample_size: sample_size} = state) do
    buffers
    |> Helpers.zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, stream_format) end)
    |> add_values(false, state)
  end

  @impl true
  def flush(state), do: add_values([], true, state)

  defp do_mix(samples, stream_format) do
    samples
    |> Enum.map(&RawAudio.sample_to_value(&1, stream_format))
    |> Enum.sum()
  end

  defp add_values(values, is_last_wave, state, buffer \\ <<>>) do
    split_fun = if state.is_wave_positive, do: &(&1 >= 0), else: &(&1 <= 0)
    {values, rest} = Enum.split_while(values, split_fun)

    if !is_last_wave && rest == [] do
      if Enum.all?(values, fn value -> value == 0 end) do
        {Enum.map(values, &RawAudio.value_to_sample(&1, state.stream_format))
         |> IO.iodata_to_binary(), state}
      else
        state = %__MODULE__{state | queue: state.queue ++ values}
        {buffer, state}
      end
    else
      buffer = [buffer | get_iodata(values, state)] |> IO.iodata_to_binary()

      state =
        state
        |> Map.put(:is_wave_positive, !state.is_wave_positive)
        |> Map.put(:queue, [])

      if is_last_wave && rest == [] do
        {buffer, state}
      else
        add_values(rest, is_last_wave, state, buffer)
      end
    end
  end

  defp get_iodata([], %__MODULE__{queue: []}), do: <<>>

  defp get_iodata(values, %__MODULE__{stream_format: stream_format, queue: queue}) do
    (queue ++ values)
    |> scale(stream_format)
    |> Enum.map(&RawAudio.value_to_sample(&1, stream_format))
  end

  defp scale(values, stream_format) do
    {min, max} = Enum.min_max(values)
    max_sample_value = RawAudio.sample_max(stream_format)
    min_sample_value = RawAudio.sample_min(stream_format)

    cond do
      min < min_sample_value -> do_scale(values, min_sample_value / min)
      max > max_sample_value -> do_scale(values, max_sample_value / max)
      true -> values
    end
  end

  defp do_scale(values, coefficient), do: Enum.map(values, &trunc(&1 * coefficient))
end
