defmodule Membrane.Element.AudioMixer.AlignerSpec do
  use ESpec, async: false
  use Bitwise
  import Enum
  alias Membrane.Caps.Audio.Raw
  alias Array

  let :empty_queue, do: Array.from_list [<<>>,<<>>,<<>>]
  let :simple_queue, do: Array.from_list [<<1,2,3>>,<<4,5,6>>,<<7,8,9>>]
  let :empty_to_drop, do: Array.from_list [0, 0, 0]

  describe ".handle_buffer/1" do
    let :buffer, do: %Membrane.Buffer{payload: payload}
    let :state, do: %{queue: queue, to_drop: to_drop}
    context "in usual case" do
      let :to_drop, do: empty_to_drop
      let :queue, do: simple_queue
      let :payload, do: <<9,8,7>>
      it "should add buffer to queue" do
        expect(described_module.handle_buffer({:sink0, buffer}, state)).to eq {:ok, [], %{state | queue: simple_queue |> Array.set(0, <<1,2,3,9,8,7>>)}}
      end
    end
    context "if buffer needs to be cut" do
      let :to_drop, do: empty_to_drop |> Array.set(1, 1)
      let :queue, do: empty_queue
      let :payload, do: <<9,8,7>>
      it "should cut buffer and add it to queue" do
        expect(described_module.handle_buffer({:sink1, buffer}, state)).to eq {:ok, [], %{
            state | queue: queue |> Array.set(1, <<8,7>>), to_drop: empty_to_drop
          }}
      end
    end
  end

  describe ".handle_other/1" do
    let :state, do: %{queue: queue, chunk_size: chunk_size, to_drop: to_drop}
    let :chunk_size, do: 3
    let :to_drop, do: empty_to_drop
    defp handle_other_ok_result([payload: payload, state: state]) do
      {
        :ok,
        [{:send, {:source, %Membrane.Buffer{payload: payload}}}],
        state
      }
    end

    context "in usual case" do
      let :queue, do: simple_queue
      it "should parse and send queue as a buffer" do
        expect(described_module.handle_other :tick, state).to eq handle_other_ok_result([
          payload: queue |> Array.to_list,
          state: %{state | queue: empty_queue}]
        )
      end
    end
    context "if sizes of queues differ" do
      context "and one of them lacks data" do
        let :queue, do: simple_queue |> Array.set(1, <<1,2>>)
        it "should forward queue and update to_drop" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result([
            payload: queue |> Array.to_list,
            state: %{state | queue: empty_queue, to_drop: Array.from_list [0, 1, 0]}
          ])
        end
      end
      context "and one of them excesses data" do
        let :queue, do: simple_queue |> Array.set(1, <<1,2,3,4>>)
        it "should forward queue and store excess in the new queue" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result([
            payload: queue |> Array.set(1, <<1,2,3>>) |> Array.to_list,
            state: %{state | queue: empty_queue |> Array.set(1, <<4>>)}
          ])
        end
      end
    end
  end
end
