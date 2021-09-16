defmodule Membrane.AudioMixer.Helpers do
  @moduledoc false

  @spec zip_longest_binary_by([binary()], integer(), ([binary()] -> any()), list()) :: list()
  def zip_longest_binary_by(binaries, chunk_size, zipper, acc \\ []) do
    {chunks, rests} =
      binaries
      |> Enum.flat_map(fn
        <<chunk::binary-size(chunk_size), rest::binary>> -> [{chunk, rest}]
        _binary -> []
      end)
      |> Enum.unzip()

    case chunks do
      [] ->
        Enum.reverse(acc)

      _chunks ->
        zip_longest_binary_by(rests, chunk_size, zipper, [zipper.(chunks) | acc])
    end
  end
end
