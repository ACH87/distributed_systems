defmodule Paxos do

  def start(name, participants, upper_layer) do
      pid = spawn(Paxos, :init, [name, participants, upper_layer])
      :global.re_register_name(name, pid)
      pid
  end

  def init(name, neighbours, upper_layer) do
      state = %{
          name: name,
          upper_layer: upper_layer,
          b: 0,
          v: 0,
          b_old: 0,
          v_old: 0,
          accepted: MapSet.new(),
          prepared: MapSet.new(),
          neighbours: neighbours,
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

  defp quorum_recieved(received_count, participants) do
    max_count = length(participants)
    received_count > 0 and max_count > 0 and trunc(received_count) >= trunc(max_count/2)
  end=

  def check_greater([], comp) do
    true
  end
  def check_greater([h|t], comp) do
    if comp > h do
      check_greater(t, comp)
    else
      false
    end
  end

  defp rank(name, [h|t], acc) do
    if h == name do
      acc
    else
      rank(name, t, acc+1)
    end
  end

  defp run(state) do
    my_pid = self()

    state = receive do

      {:start_ballot} ->
        new_ballot = trunc(rank(state) + (state.b_old / length(state.neighbours) + 1)) * length(state.neighbours)
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid ->send(pid,  {:prepare,self(),new_ballot})
          end
        end
        %{state |
          prepared: state.new_ballot == new_ballot && state.prepared || MapSet.new(),
          pending: %{
            message: {:send_accept, new_ballot},
            until: fn s -> quorum_recieved(MapSet.size(s.prepared), s.neighbours) end
          }
        }

      {:send_accept, b} ->
        {max_ballot, sender} = Enum.max(MapSet.to_list(state.prepared))
        v = max_ballot != {:none} && elem(max_ballot, 1) || state.v
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid -> send(pid,  {:accept,self(), state.b,state.v})
          end
        end
        %{state |
          prepared: MapSet.new(),
          accepted: state.b == b && state.accepted || MapSet.new(),
          pending: %{
            message: {:send_decided, b},
            until: fn s -> quorum_recieved(MapSet.size(s.accepted), s.neighbours) end
          }
        }

      {:send_decided, b} ->
        send(my_pid, {:bc_send, fn s -> s.b == b end, {:decided, state.v_old}})
        %{state | accepted: MapSet.new()}

      {:prepared, sender, b, vote_old} ->
        state.b == b && %{state | prepared: MapSet.put(state.prepared, {vote_old, sender})} || state

      {:accepted, sender, b} ->
        state.b == b && %{state | accepted: MapSet.put(state.accepted, sender)} || state

      {:propose, v} ->
        %{state | v: v}

      {:prepare, leader, b} ->
        send(leader, {:prepared, state.name, b, state.b_old > 0 && {state.b_old, state.v_old} || {:none}})
        %{state | b: b}

      {:accept, leader, b, v} ->
        send(leader, {:accepted, state.name, b})
        %{state | b_old: b, v_old: v}

      {:decided, v} ->
        send(state.upper_layer, {:decide, v})
        %{state | b: 0, accepted: MapSet.new(), prepared: MapSet.new()}

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
