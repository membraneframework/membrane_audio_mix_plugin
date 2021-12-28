defmodule Membrane.AudioMixer.BundlexProject do
  use Bundlex.Project

  def project() do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      mixer: [
        interface: :nif,
        sources: ["mixer.c"],
        pkg_configs: [],
        preprocessor: Unifex
      ]
    ]
  end
end
