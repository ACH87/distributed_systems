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

  def propose(pid, {:val, value}) do
    send(pid, {:proposed, value})
  end

  def quorum(received_count, neighbours) do
    max_count = length(neighbours)
    received_count > 0 and max_count > 0 and trunc(received_count) >= trunc(max_count/2)
  end

  defp rank(state) do
    Enum.find_index(state.neighbours, fn n -> state.name == n end)
  end

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

      {:proposed, v} ->
        %{state | v: value}

      {:start_ballot} ->
        new_ballot = trunc(rank(state.name, state.neighbours, 0) + (state.b_old / length(state.neighbours) + 1)) * length(state.neighbours)
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid ->send(pid,  {:prepare,self(),new_ballot})
          end
        end
        %{state |
          prepared: state.b == new_ballot && state.prepared || MapSet.new(),
          pending: %{
            message: {:start_accept, new_ballot},
            until: fn s -> quorum(MapSet.size(s.prepared), s.neighbours) end
          }
        }

      {:prepare, leader, b} ->
          send(leader, {:prepared, state.name, b, state.b_old > 0 && {state.b_old, state.v_old} || {:none}})
          %{state | b: b}

      {:prepared, sender, b, vote_old} ->
          state.b == b && %{state | prepared: MapSet.put(state.prepared, {vote_old, sender})} || state

      {:start_accept, b} ->
        {max_ballot, sender} = Enum.max(MapSet.to_list(state.prepared))
        v = max_ballot != {:none} && elem(max_ballot, 1) || state.v
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
	#    IO.puts('sending accept')
            pid -> send(pid,  {:accept,self(), b,v})
          end
        end
        %{state |
          prepared: MapSet.new(),
          accepted: state.b == b && state.accepted || MapSet.new(),
          pending: %{
            message: {:start_decided, b},
            until: fn s -> quorum(MapSet.size(s.accepted), s.neighbours) end
          }
        }

      {:accept, leader, b, v} ->
  #	IO.puts('accepting')
          send(leader, {:accepted, state.name, b})
          %{state | b_old: b, v_old: v}

      {:accepted, sender, b} ->
        state.b == b && %{state | accepted: MapSet.put(state.accepted, sender)} || state


      {:start_decided, b} ->
#	IO.puts('decided')
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid -> send(pid, {:decided,self(), state.v_old})
          end
        end
        %{state | accepted: MapSet.new()}

      {:decided, leader, v} ->
#	IO.puts('value decided')
        send(state.upper_layer, {:decide, v})
        %{state | b: 0, accepted: MapSet.new(), prepared: MapSet.new()}

      after 100 ->
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
