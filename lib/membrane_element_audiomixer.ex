defmodule Membrane.Element.AudioMixer do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = []

    opts = [strategy: :one_for_one, name: Membrane.Element.AudioMixer]
    Supervisor.start_link(children, opts)
  end
end
