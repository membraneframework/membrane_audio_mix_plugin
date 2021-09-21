defmodule Membrane.AudioMixer.ClipPreventer do
  @moduledoc """
  Module responsible for mixing audio tracks (all in the same format, with the same number of
  channels and sample rate). Result is a single path in the format mixed paths are encoded in.
  If overflow happens during mixing, wave will be scaled down to the max sample value.
  """

  alias Membrane.AudioMixer.Helpers
  alias Membrane.Caps.Audio.Raw

  defmodule State do
    @moduledoc """
    Structure representing `ClipPreventer` state.

    ## Keys
      - `is_wave_positive` - are values in current wave positive?
      - `queue` - queued mixed values from current wave
    """

    defstruct is_wave_positive: true, queue: []

    @type t :: %__MODULE__{
            is_wave_positive: boolean(),
            queue: [integer()]
          }
  end

  @doc """
  Mixes `buffers` to one buffer. Given buffers should have equal sizes. It uses information about
  samples provided in `caps`.
  """
  @spec mix([binary()], boolean(), Raw.t(), State.t()) :: {binary(), State.t()}
  def mix(buffers, last_wave, caps, state) do
    sample_size = Raw.sample_size(caps)

    buffers
    |> Helpers.zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, caps) end)
    |> add_values(last_wave, caps, state)
  end

  defp do_mix(samples, caps) do
    samples
    |> Enum.map(&Raw.sample_to_value(&1, caps))
    |> Enum.sum()
  end

  defp add_values(values, last_wave, caps, state, buffer \\ <<>>) do
    split_fun = if state.is_wave_positive, do: &(&1 >= 0), else: &(&1 <= 0)
    {values, rest} = Enum.split_while(values, split_fun)

    if !last_wave && rest == [] do
      state = %State{state | queue: state.queue ++ values}
      {buffer, state}
    else
      buffer = buffer <> get_buffer(values, caps, state)

      state =
        state
        |> Map.put(:is_wave_positive, !state.is_wave_positive)
        |> Map.put(:queue, [])

      if last_wave && rest == [] do
        {buffer, state}
      else
        add_values(rest, last_wave, caps, state, buffer)
      end
    end
  end

  defp get_buffer([], _caps, %State{queue: []}), do: <<>>

  defp get_buffer(values, caps, %State{queue: queue}) do
    (queue ++ values)
    |> scale(caps)
    |> Enum.map(&Raw.value_to_sample(&1, caps))
    |> IO.iodata_to_binary()
  end

  defp scale(values, caps) do
    {min, max} = Enum.min_max(values)
    max_sample_value = Raw.sample_max(caps)
    min_sample_value = Raw.sample_min(caps)

    cond do
      min < min_sample_value -> do_scale(values, min_sample_value / min)
      max > max_sample_value -> do_scale(values, max_sample_value / max)
      true -> values
    end
  end

  defp do_scale(values, coefficient), do: Enum.map(values, &trunc(&1 * coefficient))
end
