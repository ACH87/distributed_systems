defmodule Paxos do

  def start(name, participants, upper_layer) do
      pid = spawn(Paxos, :init, [name, participants, upper_layer])
      case :global.re_register_name(name, pid) do
        :yes -> IO.puts "Registered: #{name}"
        :no  -> IO.puts "Failed to register #{name}"
      end
      pid
  end

  def init(name, participants, upper_layer) do
      state = %{
          name: name,
          propsal: 0,
          current_ballot: 0,
          old_ballot: %{b_old: 0, v_old: 0},
          upper_layer: upper_layer,
          accepted_count: 0,
          received: [],
          participants: participants
      }
      run(state)
  end

  def start_ballot(pid) do
    send(pid, {:start_ballot})
  end

  def propose(pid, {:val, v}) do
    send(pid, {:propose, v})
  end

  defp is_majority(received, total) do
    :math.floor(received/2) >= :math.floor(total/2)
  end

  defp get_highest_ballot_vlaue(propsoal, old_ballots) do
    highest_ballot = 0
    value = propsoal
    for {b_old, v_old} <- old_ballots, b_old > highest_ballot do
      value = v_old
    end
    value
  end

  defp node_rank(state) do
    Enum.find_index(state.participants, fn n -> state.name == n end)
  end

  defp run(state) do
    my_pid = self()
    state = receive do
      {:start_ballot} ->
        b = trunc(node_rank(state) + (state.old_ballot.b_old / Enum.count(state.participants) + 1))
        #IO.puts("start ballot, leader: #{state.name}, ballot: #{b}")
        send(my_pid, {:bc_send, fn state -> state.old_ballot.b_old < b end, {:prepare, my_pid, b}})
        state

      {:propose, v} ->
        state = %{state | propsal: v}
        state

      {:prepared, b, old_ballot} ->
        state = %{state | received: state.received ++ [old_ballot]}
        if is_majority(Enum.count(state.received), Enum.count(state.participants)) do
          v = get_highest_ballot_vlaue(state.propsal, state.received)
          send(my_pid, {:bc_send, fn state -> state.old_ballot.b_old < b end, {:accept, my_pid, b, v}})
        end
        state

      {:accepted, b} ->
        #IO.puts "Accepted #{state.accepted_count}"
        state = %{state | accepted_count: state.accepted_count+1}
        if state.old_ballot.b_old == b and is_majority(state.accepted_count, Enum.count(state.participants)) do
          send(my_pid, {:bc_send, fn state -> state.current_ballot == b end, {:decided, state.old_ballot.v_old}})
        end
        state

      {:decided, v} ->
	IO.puts('decided')
        send(state.upper_layer, {:decide, v})
        state = %{state | current_ballot: 0, accepted_count: 0}
        state

      {:prepare, leader, b} ->
        #IO.puts "Prepare #{state.name} #{b}"
        state = %{state | current_ballot: b}
        send(leader, {:prepared, b, state.old_ballot})
        state

      {:accept, leader, b, v} ->
        #IO.puts "#{state.name} accept #{b} #{v}"
        state = %{state | old_ballot: %{b_old: b, v_old: v}}
        send(leader, {:accepted, b})
        state

      {:bc_send, condition, message} ->
        #IO.puts("#{state.name} bc_send: #{inspect message}")
        if condition.(state) do
          send(my_pid, message)
          for name <- state.participants, name != state.name do
            case :global.whereis_name(name) do
              pid -> send(pid, {:bc_send, condition, message})
              :undefined -> IO.puts("Failed to find #{name}")
            end
          end
        end
        state
    end

    run(state)
  end

end

