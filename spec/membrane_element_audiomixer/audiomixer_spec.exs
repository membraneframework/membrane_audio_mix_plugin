defmodule Membrane.Element.AudioMixer.MixerSpec do
  use ESpec, async: false
  use Bitwise
  alias Membrane.Caps.Audio.Raw, as: Caps

  describe ".handle_buffer/1" do
    let :state, do: Nil
    let :caps, do: %Caps{format: format}
    let :buffer, do: %Membrane.Buffer{payload: %{data: data, remaining_samples_cnt: remaining_samples_cnt}}
    let :remaining_samples_cnt, do: 0
    defp handle_buffer_ok_result [payload: payload, state: state] do
        {:ok, [{:send, {:source, %Membrane.Buffer{payload: payload}}}], state}
    end

    context "in usual case" do
      let :format, do: :s16le
      let :remaining_samples_cnt, do: 0
      let :data, do: [<<1, 0, 3, 0>>, <<2, 0, 4, 0>>]
      it "should properly sum chunks" do
        expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<3, 0, 7, 0>>, state: state]
      end
    end
    context "if lenghts of chunks differ" do
      let :format, do: :s16le
      let :remaining_samples_cnt, do: 0
      let :data, do: [<<1, 0, 3, 0>>, <<2, 0, 4, 0, 5, 0>>]
      it "should sum adjacent samples and copy the rest" do
        expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<3, 0, 7, 0, 5, 0>>, state: state]
      end
    end
    context "if format is signed" do
      let :format, do: :s16le
      let :remaining_samples_cnt, do: 0
      context "and there is overflow" do
        let :data, do: [<<255, 127>>, <<1, 0>>]
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<255, 127>>, state: state]
        end
      end
      context "and there is underflow" do
        let :data, do: [<<0,128>>, <<255,255>>]
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<0, 128>>, state: state]
        end
      end
    end
    context "if format is unsigned" do
      let :format, do: :u16le
      let :remaining_samples_cnt, do: 0
      let :data, do: [<<255, 255>>, <<1, 0>>]
      context "and there is overflow" do
        it "should cut value" do
          expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<255,255>>, state: state]
        end
      end
    end
    context "if remaining_samples_cnt is positive" do
      let :format, do: :s16le
      let :remaining_samples_cnt, do: 2
      let :data, do: [<<1, 0, 3, 0>>, <<2, 0, 4, 0>>]
      it "should add a remaining_samples_cnt-long silent part to the mixed data" do
        expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<3, 0, 7, 0, 0, 0, 0, 0>>, state: state]
      end
    end
    context "if some paths contain incomplete sample" do
      let :format, do: :s16le
      let :remaining_samples_cnt, do: 0
      context "and one of them is the longest path" do
        let :data, do: [<<1, 0, 3, 0, 5>>, <<2, 0, 4, 0>>, <<1,0,3>>]
        it "should skip incomplete samples" do
          expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<4, 0, 7, 0>>, state: state]
        end
      end
      context "and none of them is the longest path" do
        let :data, do: [<<1, 0, 3, 0>>, <<2>>, <<1, 0, 3>>]
        it "should skip incomplete samples" do
          expect(described_module.handle_buffer(:sink, buffer, caps, state)).to eq handle_buffer_ok_result [payload: <<2, 0, 3, 0>>, state: state]
        end
      end
    end
  end
end
