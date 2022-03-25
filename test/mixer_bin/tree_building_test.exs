defmodule Membrane.AudioMixerBin.TreeBuildingTest do
  use ExUnit.Case, async: true

  import Membrane.ParentSpec

  alias Membrane.AudioMixerBin, as: Bin
  alias Membrane.AudioMixer, as: Opts
  alias Membrane.ParentSpec

  test "single mixing node" do
    opts = %Opts{}

    pads = [
      %{ref: :a, options: %{offset: 1}},
      %{ref: :b, options: %{offset: 2}},
      %{ref: :c, options: %{offset: 3}},
      %{ref: :d, options: %{offset: 4}}
    ]

    assert %ParentSpec{children: children, links: links} = Bin.gen_mixing_spec(pads, 4, opts)
    assert children == [{"mixer_0_0", opts}]
    links = MapSet.new(links)

    assert MapSet.member?(links, link("mixer_0_0") |> to_bin_output())

    for %{ref: ref, options: %{offset: offset}} <- pads do
      link = link_bin_input(ref) |> via_in(:input, options: [offset: offset]) |> to("mixer_0_0")
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

    assert %ParentSpec{children: children, links: links} = Bin.gen_mixing_spec(pads, 2, opts)
    assert children == [{"mixer_0_0", opts}, {"mixer_1_0", opts}, {"mixer_1_1", opts}]
    links = MapSet.new(links)

    assert MapSet.member?(links, link("mixer_0_0") |> to_bin_output())

    assert MapSet.member?(links, link("mixer_1_0") |> to("mixer_0_0"))
    assert MapSet.member?(links, link("mixer_1_1") |> to("mixer_0_0"))

    expected_mixers = [0, 1, 0, 1]

    pads
    |> Enum.zip(expected_mixers)
    |> Enum.each(fn {%{ref: ref, options: %{offset: offset}}, mixer_idx} ->
      link =
        link_bin_input(ref)
        |> via_in(:input, options: [offset: offset])
        |> to("mixer_1_#{mixer_idx}")

      assert MapSet.member?(links, link)
    end)
  end
end
