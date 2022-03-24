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
        sources: ["mixer.c", "caps_audio_raw.c"],
        deps: [membrane_common_c: :membrane, unifex: :unifex],
        preprocessor: Unifex
      ]
    ]
  end
end
