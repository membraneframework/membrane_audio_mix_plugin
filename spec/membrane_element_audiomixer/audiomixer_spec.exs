defmodule Membrane.Element.AudioMixer.MixerSpec do
  use ESpec, async: false

  describe ".handle_buffer/1" do
    let :state, do: %{sample_size: sample_size}
    let :sample_size, do: 2
    let :buffer, do: %Membrane.Buffer{payload: payload}
    let :payload, do: [<<1, 0, 3, 0, 5>>, <<2, 0, 4, 0, 6>>]
    it "should return ok result" do
      expect(described_module.handle_buffer({:sink, buffer}, state)).to be_ok_result
    end
    it "should properly sum chunks" do
      expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<3, 0>>, <<7, 0>>]}
    end
  end
end
