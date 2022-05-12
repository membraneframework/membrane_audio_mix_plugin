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
        deps: [membrane_common_c: :membrane_raw_audio, unifex: :unifex],
        preprocessor: Unifex
      ]
    ]
  end
end
