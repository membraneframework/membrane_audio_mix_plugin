defmodule Membrane.Element.AudioMixer.AlignerSpec do
  use ESpec, async: false
  use Bitwise
  import Enum
  alias Array
  alias Membrane.Caps.Audio.Raw, as: Caps

  let :now, do: 0.1

  before do: allow(Membrane.Time).to accept(:native_monotonic_time, fn -> now end)
  before do: allow(Membrane.Time).to accept(:native_resolution, fn -> 1 end)

  let :empty_queue, do: Array.from_list [<<>>,<<>>,<<>>]
  let :simple_queue, do: Array.from_list
  let :empty_to_drop, do: Array.from_list [0, 0, 0]
  defp to_sink_data list do
    list
      |> with_index
      |> into(%{}, fn {{q, d}, i} -> {i, %{queue: q, to_drop: d, first_play: false}} end)
  end
  let :empty_sink_data, do: 0..2 |> map(fn _ -> {<<>>, 0} end) |> to_sink_data
  let :simple_sink_data, do: [{<<1,2,3,4,5,6>>, 0},{<<7,8,9,10,11,12>>, 0},{<<13,14,15,16,17,18>>, 0}] |> to_sink_data
  let :caps, do: Nil

  describe ".handle_other/1" do
    context "{sink, Membrane.Buffer}" do
      let :buffer, do: %Membrane.Buffer{payload: payload}
      let :state, do: %{sink_data: sink_data}
      context "in usual case" do
        let :sink_data, do: simple_sink_data
        let :payload, do: <<9,8,7>>
        it "should add buffer to queue" do
          expect(described_module.handle_other({0, buffer}, state)).to eq {
            :ok, %{state | sink_data: simple_sink_data |> Map.update!(0, &%{&1 | queue: <<1,2,3,4,5,6,9,8,7>>})}
          }
        end
      end
      context "if buffer needs to be cut" do
        let :sink_data, do: empty_sink_data |> Map.update!(1, &%{&1 | to_drop: 1})
        let :payload, do: <<9,8,7>>
        it "should cut buffer and add it to queue" do
          expect(described_module.handle_other({1, buffer}, state)).to eq {:ok, %{
              state | sink_data: empty_sink_data |> Map.update!(1, &%{&1 | queue: <<8,7>>})
            }}
        end
      end
    end
    context ":tick" do
      let :state, do: %{sink_data: sink_data, sinks_to_remove: sinks_to_remove, caps: %Caps{sample_rate: 1000, format: :s24le, channels: 1}, previous_tick: 0.098, buffer_reserve_factor: 0.5}
      let :sinks_to_remove, do: []
      defp handle_other_ok_result [data: data, remaining_samples_cnt: remaining_samples_cnt, state: state] do
        {
          :ok,
          [{:send, {:source, %Membrane.Buffer{payload: %{data: data, remaining_samples_cnt: remaining_samples_cnt}}}}],
          %{state | previous_tick: now}
        }
      end

      defp queues sink_data do
        sink_data |> Map.values |> map(fn %{queue: q} -> q end)
      end

      context "in usual case" do
        let :sink_data, do: simple_sink_data
        it "should parse and send queue as a buffer" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
            data: sink_data |> queues,
            remaining_samples_cnt: 0,
            state: %{state | sink_data: empty_sink_data}
          ]
        end
      end
      context "if there are no sinks" do
        let :sink_data, do: [] |> to_sink_data
        it "should send an empty payload, and set remaining_samples_cnt to amount of samples corresponding entire time gap" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
            data: sink_data |> queues,
            remaining_samples_cnt: 2,
            state: %{state | sink_data: sink_data}
          ]
        end
      end
      context "if some sinks have not received initial amount of data yet" do
        let :sink_data, do: simple_sink_data |> Map.update!(1, &%{&1 | first_play: true})
        it "should skip them while constructing payload, preserve their queue, and leave update to_drop and first_play unchanged" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
            data: sink_data |> Map.delete(1) |> queues,
            remaining_samples_cnt: 0,
            state: %{state | sink_data: empty_sink_data |> Map.update!(1, &%{&1 | queue: simple_sink_data[1].queue, first_play: true})}
          ]
        end
      end
      context "if some sinks have just received initial amount of data" do
        let :sink_data, do: simple_sink_data |> Map.update!(1, &%{&1 | queue: simple_sink_data[1].queue <> <<80, 81, 82>>, first_play: true})
        it "should add their buffer to payload, excess to queue, leave to_drop unchanged and set first_play to false" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
            data: sink_data |> Map.update!(1, &%{&1 | queue: simple_sink_data[1].queue}) |> queues,
            remaining_samples_cnt: 0,
            state: %{state | sink_data: empty_sink_data |> Map.update!(1, &%{&1 | queue: <<80, 81, 82>>, first_play: false})}
          ]
        end
      end
      context "if there are some sinks to remove" do
        let :sink_data, do: simple_sink_data
        let :sinks_to_remove, do: [1]
        it "should parse and send queue as a buffer" do
          expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
            data: sink_data |> queues,
            remaining_samples_cnt: 0,
            state: %{state | sink_data: empty_sink_data |> Map.delete(1), sinks_to_remove: []}
          ]
        end
      end
      context "if sizes of queues differ" do
        context "and one of them lacks data" do
          let :sink_data, do: simple_sink_data |> Map.update!(1, &%{&1 | queue: <<1,2,3>>})
          it "should forward queue and update to_drop" do
            expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
              data: sink_data |> queues,
              remaining_samples_cnt: 0,
              state: %{state | sink_data: empty_sink_data |> Map.update!(1, &%{&1 | to_drop: 3})}
            ]
          end
        end
        context "and one of them excesses data" do
          let :sink_data, do: simple_sink_data |> Map.update!(1, &%{&1 | queue: <<1,2,3,4,5,6,7,8,9>>})
          it "should forward queue and store excess in the new queue" do
            expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
              data: simple_sink_data |> Map.update!(1, &%{&1 | queue: <<1,2,3,4,5,6>>}) |> queues,
              remaining_samples_cnt: 0,
              state: %{state | sink_data: empty_sink_data |> Map.update!(1, &%{&1 | queue: <<7,8,9>>})}
            ]
          end
        end
        context "and all of them lack data" do
          let :sink_data, do: [{<<1,2,3>>, 0}, {<<1,2,3>>, 0}, {<<>>, 0}] |> to_sink_data
          it "should forward queue, update to_drop and set remaining_samples_cnt" do
            expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
              data: sink_data |> queues,
              remaining_samples_cnt: 1,
              state: %{state | sink_data: [{<<>>, 3}, {<<>>, 3}, {<<>>, 6}] |> to_sink_data}
            ]
          end
          context "and size of longest path is not an integer multiplication of sample size" do
            let :sink_data, do: empty_sink_data |> Map.update!(1, &%{&1 | queue: <<1,2,3,4,5>>})
            it "should forward queue, update to_drop and set remaining_samples_cnt skipping incomplete sample" do
              expect(described_module.handle_other :tick, state).to eq handle_other_ok_result [
                data: sink_data |> queues,
                remaining_samples_cnt: 1,
                state: %{state | sink_data: [{<<>>, 6}, {<<>>, 1}, {<<>>, 6}] |> to_sink_data}
              ]
            end
          end
        end
      end
    end
  end
end
