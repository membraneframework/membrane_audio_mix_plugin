defmodule Membrane.Element.AudioMixer.DoMixSpec do
  use ESpec, async: false
  use Bitwise
  alias Membrane.Caps.Audio.Raw, as: Caps
  alias Membrane.Event.Discontinuity.Payload, as: Discontinuity
  alias Membrane.Buffer

  let :state, do: nil
  let :caps, do: %Caps{format: format}

  describe ".handle_event/1" do
    context "discontinuity" do
      let :format, do: :s16le
      it "should produce silence of length equal to discontinuity" do
        res = described_module.handle_event(:sink, caps, %Membrane.Event{payload: %Discontinuity{duration: 2}}, state)
        expect(res).to eq {:ok, [send: {:source, %Buffer{payload: <<0,0,0,0>>}}], state}
      end
    end
  end

  describe ".handle_buffer/1" do
    let :buffer, do: %Buffer{payload: payload}
    defp handle_buffer_ok_result [payload: payload, state: state] do
        {:ok, [{:send, {:source, %Buffer{payload: payload}}}], state}
    end

    context "in usual case" do
      let :format, do: :s16le
      let :payload, do: [[<<1, 0, 3, 0>>], [<<2>>, <<0, 4, 0>>]]
      it "should properly sum chunks" do
        expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<3, 0, 7, 0>>, state: state]
      end
    end
    context "if lenghts of chunks differ" do
      let :format, do: :s16le
      let :payload, do: [[<<1, 0>>, <<3, 0>>], [<<2, 0, 4, 0, 5, 0>>]]
      it "should sum adjacent samples and copy the rest" do
        expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<3, 0, 7, 0, 5, 0>>, state: state]
      end
    end
    context "if format is signed" do
      let :format, do: :s16le
      context "and there is overflow" do
        let :payload, do: [[<<255, 127>>], [<<1, 0>>]]
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<255, 127>>, state: state]
        end
      end
      context "and there is underflow" do
        let :payload, do: [[<<0,128>>], [<<255,255>>]]
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<0, 128>>, state: state]
        end
      end
    end
    context "if format is unsigned" do
      let :format, do: :u16le
      let :discontinuity, do: 0
      let :payload, do: [[<<255>>, <<255>>], [<<1, 0>>]]
      context "and there is overflow" do
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<255,255>>, state: state]
        end
      end
    end
    context "if data is an empty list" do
      let :format, do: :s16le
      let :payload, do: []
      it "should send empty payload" do
        expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<>>, state: state]
      end
    end
    context "if some paths contain incomplete sample" do
      let :format, do: :s16le
      context "and one of them is the longest path" do
        let :payload, do: [[<<1, 0, 3, 0, 5>>], [<<2, 0, 4, 0>>], [<<1,0,3>>]]
        it "should skip incomplete samples" do
          expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<4, 0, 7, 0>>, state: state]
        end
      end
      context "and none of them is the longest path" do
        let :payload, do: [[<<1, 0, 3, 0>>], [<<2>>], [<<1, 0, 3>>]]
        it "should skip incomplete samples" do
          expect(described_module.handle_buffer(:sink, caps, buffer, state)).to eq handle_buffer_ok_result [payload: <<2, 0, 3, 0>>, state: state]
        end
      end
    end
  end
end
