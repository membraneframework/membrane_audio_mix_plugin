defmodule Membrane.AudioMix.Mixfile do
  use Mix.Project

  @version "0.6.0"
  @github_url "https://github.com/membraneframework/membrane_audio_mix_plugin"

  def project do
    [
      app: :membrane_audio_mix_plugin,
      version: @version,
      elixir: "~> 1.12",
      compilers: Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Plugin performing raw audio mixing and interleaving.",
      package: package(),
      name: "Membrane Audio Mix plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 0.9.0"},
      {:membrane_raw_audio_format, "~> 0.8.0"},
      {:bunch, "~> 1.3"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false},
      {:membrane_file_plugin, "~> 0.8", only: :test},
      {:membrane_mp3_mad_plugin, "~> 0.10", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Membrane.AudioMixer,
        Membrane.AudioInterleaver
      ],
      groups_for_modules: [
        Mixer: [
          ~r/^Membrane\.AudioMixer.*/
        ],
        Interleaver: [
          ~r/^Membrane\.AudioInterleaver.*/
        ]
      ]
    ]
  end
end
