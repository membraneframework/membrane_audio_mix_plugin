defmodule Membrane.Element.AudioMixer.Mixfile do
  use Mix.Project

  def project do
    [app: :membrane_element_audiomixer,
     compilers: Mix.compilers,
     version: "0.0.1",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     description: "Membrane Multimedia Framework (AudioConvert Element)",
     maintainers: ["Mateusz Front"],
     licenses: ["LGPL"],
     name: "Membrane Element: AudioMixer",
     source_url: "https://github.com/membraneframework/membrane-element-audiomixer",
     deps: deps()]
  end

  def application do
    [applications: [
      :membrane_core
      ], mod: {Membrane.Element.AudioMixer, []}]
  end

  defp elixirc_paths(_),     do: ["lib",]

  defp deps do
    [
      {:membrane_core, git: "git@github.com:membraneframework/membrane-core.git", branch: "feature/pull"},
      {:membrane_caps_audio_raw, git: "git@github.com:membraneframework/membrane-caps-audio-raw.git"},
      {:espec, "~> 1.1.2", only: :test},
      {:ex_doc, "~> 0.14", only: :dev},
      {:qex, "~> 0.3"},
    ]
  end
end
