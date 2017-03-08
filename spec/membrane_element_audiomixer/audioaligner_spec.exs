defmodule Membrane.Element.AudioMixer.AlignerSpec do
  use ESpec, async: false
  use Bitwise
  alias Membrane.Caps.Audio.Raw
  alias Array

  let :empty_queue, do: Array.from_list [<<>>,<<>>,<<>>]
  let :simple_queue, do: Array.from_list [<<1,2,3>>,<<4,5,6>>,<<7,8,9>>]

  describe ".handle_buffer/1" do
    let :buffer, do: %Membrane.Buffer{payload: payload}
    let :state, do: %{queue: queue}
    context "in usual case" do
      let :queue, do: simple_queue
      let :payload, do: <<9,8,7>>
      it "should add buffer to queue" do
        expect(described_module.handle_buffer({:sink0, buffer}, state)).to eq {:ok, [], %{state | queue: simple_queue |> Array.set(0, <<1,2,3,9,8,7>>)}}
      end
    end
  end

  describe ".handle_other/1" do
    let :state, do: %{queue: queue, chunk_size: chunk_size, to_drop: to_drop}

    context "in usual case" do
      let :queue, do: simple_queue
      let :chunk_size, do: 3
      let :to_drop, do: Array.from_list [0,0,0]
      it "should parse and send queue as a buffer" do
        expect(described_module.handle_other :tick, state).to eq {
          :ok,
          [{:send, {:source, %Membrane.Buffer{payload: [<<1,2,3>>,<<4,5,6>>,<<7,8,9>>]}}}],
          %{state | queue: empty_queue}
        }
      end
    end
  end
end
