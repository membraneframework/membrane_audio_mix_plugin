defmodule CapsHelper do

  def value_to_sample(value, :s16le) do
    {:ok, <<value::integer-unit(8)-size(2)-little-signed>>}
  end

  def value_to_sample(value, :u16le) do
    {:ok, <<value::integer-unit(8)-size(2)-little-unsigned>>}
  end

  def value_to_sample!(value, format) do
    {:ok, sample} = value_to_sample(value, format)
    sample
  end

  def is_signed(:s16le) do true end
  def is_signed(:u16le) do false end

end
