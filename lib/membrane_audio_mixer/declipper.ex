defmodule Membrane.AudioMixer.Declipper do
  @moduledoc false

  alias Membrane.AudioMixer.Helpers
  alias Membrane.Caps.Audio.Raw

  defmodule State do
    @moduledoc false

    @enforce_keys [:caps]
    defstruct @enforce_keys ++ [is_wave_positive: true, values: []]

    @type t :: %__MODULE__{
            caps: Raw.t(),
            is_wave_positive: boolean(),
            values: [integer()]
          }
  end

  @spec mix([binary()], boolean(), State.t()) :: {binary(), State.t()}
  def mix(buffers, last_wave, %State{caps: caps} = state) do
    sample_size = Raw.sample_size(caps)

    buffers
    |> Helpers.zip_longest_binary_by(sample_size, fn buf -> do_mix(buf, state) end)
    |> add_values(last_wave, state)
  end

  defp do_mix(samples, %State{caps: caps}) do
    samples
    |> Enum.map(&Raw.sample_to_value(&1, caps))
    |> Enum.sum()
  end

  defp add_values(values, last_wave, state, buffer \\ <<>>) do
    split_fun = if state.is_wave_positive, do: &(&1 >= 0), else: &(&1 <= 0)
    {values, rest} = Enum.split_while(values, split_fun)

    if !last_wave && rest == [] do
      state = %State{state | values: state.values ++ values}
      {buffer, state}
    else
      buffer = buffer <> get_buffer(values, state)

      state =
        state
        |> Map.put(:is_wave_positive, !state.is_wave_positive)
        |> Map.put(:values, [])

      if last_wave && rest == [] do
        {buffer, state}
      else
        add_values(rest, last_wave, state, buffer)
      end
    end
  end

  defp get_buffer([], %State{values: []}), do: <<>>

  defp get_buffer(new_values, %State{caps: caps, values: values}) do
    (values ++ new_values)
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
