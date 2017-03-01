defmodule Membrane.Element.AudioMixer.MixerSpec do
  use ESpec, async: false
  use Bitwise

  describe ".handle_buffer/1" do
    let :state, do: %{sample_size: sample_size}
    let :sample_size, do: 2
    let :buffer, do: %Membrane.Buffer{payload: payload}
    context "in usual case" do
      let :payload, do: [<<1, 0, 3, 0, 5>>, <<2, 0, 4, 0, 6>>]
      it "should return ok result" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to be_ok_result
      end
      it "should properly sum chunks" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<3, 0>>, <<7, 0>>]}
      end
    end
    context "if there is overflow" do
      let :payload, do: [<<255, 127>>, <<1, 0>>]
      it "should cut value" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<255, 127>>]}
      end
    end
    context "if there is underflow" do
      let :payload, do: [<<0,128>>, <<255,255>>]
      it "should cut value" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<0, 128>>]}
      end
    end
  end
end
