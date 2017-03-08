defmodule Membrane.Element.AudioMixer.MixerSpec do
  use ESpec, async: false
  use Bitwise
  alias Membrane.Caps.Audio.Raw

  describe ".handle_buffer/1" do
    let :state, do: %{caps: %Raw{format: format}}
    let :buffer, do: %Membrane.Buffer{payload: payload}
    context "in usual case" do
      let :format, do: :s16le
      let :payload, do: [<<1, 0, 3, 0, 5>>, <<2, 0, 4, 0, 6>>]
      it "should return ok result" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to be_ok_result
      end
      it "should properly sum chunks" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<3, 0>>, <<7, 0>>]}
      end
    end
    context "if lenghts of chunks differ" do
      let :format, do: :s16le
      let :payload, do: [<<1, 0, 3, 0, 5, 0>>, <<2, 0, 4, 0>>]
      it "should sum adjacent chunks and copy the rest" do
        expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<3, 0>>, <<7, 0>>, <<5, 0>>]}
      end
    end
    context "if format is signed" do
      let :format, do: :s16le
      context "and there is overflow" do
        let :payload, do: [<<255, 127>>, <<1, 0>>]
        it "should cut value" do
          expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<255, 127>>]}
        end
      end
      context "and there is underflow" do
        let :payload, do: [<<0,128>>, <<255,255>>]
        it "should cut value" do
          expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<0, 128>>]}
        end
      end
    end
    context "if format is unsigned" do
      let :format, do: :u16le
      let :payload, do: [<<255, 255>>, <<1, 0>>]
      context "and there is overflow" do
        it "should cut value" do
          expect(described_module.handle_buffer({:sink, buffer}, state)).to eq {:ok, [<<255,255>>]}
        end
      end
    end
  end
end
