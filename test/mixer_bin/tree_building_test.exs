defmodule Membrane.AudioMixerBin.TreeBuildingTest do
  use ExUnit.Case, async: true

  import Membrane.ChildrenSpec

  alias Membrane.AudioMixer, as: Opts
  alias Membrane.AudioMixerBin, as: Bin

  test "single mixing node" do
    opts = %Opts{}

    pads = [
      %{ref: :a, options: %{offset: 1}},
      %{ref: :b, options: %{offset: 2}},
      %{ref: :c, options: %{offset: 3}},
      %{ref: :d, options: %{offset: 4}}
    ]

    assert structure = Bin.gen_mixing_spec(pads, 4, opts)
    assert child({:mixer, {0, 0}}, opts) in structure
    links = MapSet.new(structure)

    assert MapSet.member?(links, get_child({:mixer, {0, 0}}) |> bin_output())

    for %{ref: ref, options: %{offset: offset}} <- pads do
      link =
        bin_input(ref) |> via_in(:input, options: [offset: offset]) |> get_child({:mixer, {0, 0}})

      assert MapSet.member?(links, link)
    end
  end

  test "binary tree" do
    opts = %Opts{}

    pads = [
      %{ref: :a, options: %{offset: 1}},
      %{ref: :b, options: %{offset: 2}},
      %{ref: :c, options: %{offset: 3}},
      %{ref: :d, options: %{offset: 4}}
    ]

    assert structure = Bin.gen_mixing_spec(pads, 2, opts)

    assert child({:mixer, {0, 0}}, opts) in structure
    assert child({:mixer, {1, 0}}, opts) in structure
    assert child({:mixer, {1, 1}}, opts) in structure

    links = MapSet.new(structure)

    assert MapSet.member?(links, get_child({:mixer, {0, 0}}) |> bin_output())

    assert MapSet.member?(links, get_child({:mixer, {1, 0}}) |> get_child({:mixer, {0, 0}}))
    assert MapSet.member?(links, get_child({:mixer, {1, 1}}) |> get_child({:mixer, {0, 0}}))

    expected_mixers = [0, 1, 0, 1]

    pads
    |> Enum.zip(expected_mixers)
    |> Enum.each(fn {%{ref: ref, options: %{offset: offset}}, mixer_idx} ->
      link =
        bin_input(ref)
        |> via_in(:input, options: [offset: offset])
        |> get_child({:mixer, {1, mixer_idx}})

      assert MapSet.member?(links, link)
    end)
  end
end
