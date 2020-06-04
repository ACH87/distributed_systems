defmodule Paxos do

  @log false

  def start(name, participants, upper_layer) do
      pid = spawn(Paxos, :init, [name, participants, upper_layer])
      :global.re_register_name(name, pid)
      pid
  end

  def init(name, participants, upper_layer) do
      state = %{
          name: name,
          upper_layer: upper_layer,
          b: 0,
          v: 0,
          b_old: 0,
          v_old: 0,
          accepted: MapSet.new(),
          prepared: MapSet.new(),
          participants: participants,
          pending: :none
      }
      run(state)
  end

  def start_ballot(pid) do
    send(pid, {:start_ballot})
  end

  def propose(pid, {:val, v}) do
    send(pid, {:propose, v})
  end

  defp is_majority(received_count, participants) do
    max_count = Enum.count(participants)
    received_count > 0 and max_count > 0 and trunc(received_count) >= trunc(max_count/2)
  end

  defp node_rank(state) do
    Enum.find_index(state.participants, fn n -> state.name == n end)
  end

  defp run(state) do
    my_pid = self()

    state = receive do

      {:start_ballot} ->
        new_ballot = trunc(node_rank(state) + (state.b_old / Enum.count(state.participants) + 1))
        for p <- state.participants do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid ->send(pid,  {:prepare,self(),new_ballot})
          end
        end
        %{state |
          prepared: state.b == new_ballot && state.prepared || MapSet.new(),
          pending: %{
            message: {:send_accept, new_ballot},
            until: fn s -> is_majority(MapSet.size(s.prepared), s.participants) end
          }
        }

      {:send_accept, b} ->
        @log && IO.puts "#{state.name}: majority prepared, count #{Enum.count(state.prepared)}"
        {max_ballot, sender} = Enum.max(MapSet.to_list(state.prepared))
        v = max_ballot != {:none} && elem(max_ballot, 1) || state.v
        for p <- state.participants do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid -> send(pid,  {:accept,self(), b,v})
          end
        end
        %{state |
          prepared: MapSet.new(),
          accepted: state.b == b && state.accepted || MapSet.new(),
          pending: %{
            message: {:send_decided, b},
            until: fn s -> is_majority(MapSet.size(s.accepted), s.participants) end
          }
        }

      {:send_decided, b} ->
        @log && IO.puts "#{state.name}: majority accepted, count #{MapSet.size(state.accepted)}"
        for p <- state.participants do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid -> send(pid, {:decided,self(), state.v})
          end
        end
        %{state | accepted: MapSet.new()}

      {:prepared, sender, b, vote_old} ->
        @log && IO.puts "#{state.name}: prepared #{b} #{inspect vote_old}"
        state.b == b && %{state | prepared: MapSet.put(state.prepared, {vote_old, sender})} || state

      {:accepted, sender, b} ->
        @log && IO.puts "#{state.name}: accepted #{b}"
        state.b == b && %{state | accepted: MapSet.put(state.accepted, sender)} || state

      {:propose, v} ->
        @log && IO.puts "#{state.name}: propose #{v}"
        %{state | v: v}

      {:prepare, leader, b} ->
        @log && IO.puts "#{state.name}: prepare #{b}"
        send(leader, {:prepared, state.name, b, state.b_old > 0 && {state.b_old, state.v_old} || {:none}})
        %{state | b: b}

      {:accept, leader, b, v} ->
        @log && IO.puts "#{state.name}: accept b#{b}, v#{v}"
        send(leader, {:accepted, state.name, b})
        %{state | b_old: b, v_old: v}

      {:decided, v} ->
        send(state.upper_layer, {:decide, v})
        %{state | b: 0, accepted: MapSet.new(), prepared: MapSet.new()}

      {:bc_send, condition, message} ->
        if condition.(state) do
          send(my_pid, message)
          send(my_pid, {:relay, {:bc_send, condition, message}})
        end
        state

      {:relay, message} ->
        for name <- state.participants, name != state.name do
          case :global.whereis_name(name) do
            :undefined -> :undefined
            pid -> send(pid, message)
          end
        end
        state

      after 50 ->
        if state.pending != :none and state.pending.until.(state) do
          send(my_pid, state.pending.message)
          %{state | pending: :none}
        else
          state
        end
    end

    run(state)
  end

end
