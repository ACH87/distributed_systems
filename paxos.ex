defmodule Paxos do

  def start(name, participants, upper_layer) do

    if not Enum.member?(participants, name) do
      {:error, 'participants must contain member'}

    else
      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(Paxos, :init, [name, 0, participants, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> :error
        IO.puts('registed')
      end

    end
  end

  def propose(pid, value) do
#    IO.puts('proposed value')
#    IO.puts(pid)
    send(pid, {:proposed, elem(value, 1)})
  end

  def start_ballot(bcast) do
    # ballot = :rand.uniform(100)
    send(bcast, {:lead_prepare})
  end

  def init(name, next, neighbours, upper) do
    # layers state, then hands control to the run functions
    state = %{
        name: name,
        next: next,
        upper: upper,
        received: MapSet.new(),  # set of {pid, seqno} pairs
        neighbours: neighbours,
        v: 0,
        counter: 0,
        accepted_counter: 0,
        b: 1,
        b_old: 0,
        v_old: :none,
        current_vote: 0,
        leader: :none
     }
     run(state)
  end

  defp run(state) do
    my_pid = self()

    # executes logic, state machine, accepting the application in inputs and other processes , relay message
    # race condition when a decide attempts two or more operations at the same time
    my_pid = self()
    # communication layer inputs via message i
    state = receive do
      {:proposed, value} ->
#        IO.puts('#{state.name} #{'proposing value'} #{value}')
        state = %{ state | v: value }
	#IO.puts(state.received)
        state

      {:lead_prepare} ->
        new_ballot = rank(state.name, state.neighbours, 0) + (state.b_old / length(state.neighbours) + 1)
         * length(state.neighbours)
         # enter prepare phase
#	IO.puts('#{'new ballot'} #{state.name} #{new_ballot}')
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid ->send(pid,  {:prepare,self(),new_ballot})
          end
        end
        state = %{ state | b: new_ballot, b_old: new_ballot }
        state

      {:prepared, b, c} ->
        if c != :none && c.b_old > state.b do
          # state = %{ state | v: c.v_old, b_old: c.b_old, counter: state.counter+1 }
          state = %{ state | counter: state.counter+1, b: c.b_old, v: c.v_old }
        else
          state = state = %{state | counter: state.counter+1}
        end
        if state.counter >= trunc(length(state.neighbours)/2) +1 do
          for p <- state.neighbours do

            case :global.whereis_name(p) do
              :undefined -> :undefined
              pid -> send(pid,  {:accept,self(), state.b,state.v})
            end
          end
        end
        state
      {:accepted, b} ->
          state = %{ state | accepted_counter: state.accepted_counter+1 }
         if state.accepted_counter >= trunc(length(state.neighbours)/2) +1 && state.leader == :none do
           state = %{ state | leader: self() }
            for p <- state.neighbours do
              case :global.whereis_name(p) do
                :undefined -> :undefined
                pid -> send(pid, {:decided,self(), state.v})
              end
            end
           # else
             # send(state.upper, 'antoher leader elected')
         end
          state

      {:accept,sender,b,v} ->
#        if state.leader != :none do
        # IO.puts('#{'old ballot'} #{state.b_old} #{b}')
        if state.b_old < b  do
          state = %{ state | b_old: b, v_old: v }
          send(sender, {:accepted, b})
       end
        state

      {:prepare, sender, b} ->
#	IO.puts('#{'leader attempting'} #{b}')
        if state.b_old < b do
         if state.b_old == 0 do
            send(sender, {:prepared, b, :none})
            state = %{state | current_vote: b}
          else
            send(sender, {:prepared, b, %{b_old: state.b_old, v_old: state.v_old}})
            state = %{state | current_vote: b}
            #state = %{state | current_vote: b}]
          end
        end
        state

      {:decided, sender, v} ->
#	if state.leader == :none do
        state = %{ state | v_old: v, leader: sender}
        send(state.upper, {:decide, v})
#	end
        state

      _ -> state

    end
    run(state)
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

end
