defmodule Paxos do

  # start paxos instance
  def start(name, participants, upper_layer) do

    if not Enum.member?(participants, name) do
      {:error, 'participants must contain member'}

    else
      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(Paxos, :init, [name, participants, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> :error
        IO.puts('registed')
      end

    end
  end

  def init(name, neighbours, upper_layer) do
    # b is the current ballot
    # v is the proposes value
    # accepted map is the map storing who sent accepted_counter
    # prepared says who startedprepare
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

  # start a ballot by sending "start ballot"
  def start_ballot(pid) do
    send(pid, {:start_ballot})
  end

  # propose a value for a ballot
  def propose(pid, {:val, value}) do
    send(pid, {:proposed, value})
  end

  # if theres a quroum
  def quorum(received_count, neighbours) do
    max_count = length(neighbours)
    received_count > 0 and max_count > 0 and trunc(received_count) >= trunc(max_count/2)
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

    # calculate the index of process inside a list
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

      # set state value to proposes value
      {:proposed, value} ->
        %{state | v: value}

      # start a ballot
      {:start_ballot} ->
        # find new ballot number hgiher than what has been sentbeofre
        new_ballot = trunc(rank(state.name, state.neighbours, 0) + (state.b_old / length(state.neighbours) + 1)) * length(state.neighbours)
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid ->send(pid,  {:prepare,self(),new_ballot})
          end
        end
        # add prepared state to true and have a pending map, lambda function to check if a quroum has been recieved
        # if quorum is recieves start the accept phase
        %{state |
          prepared: state.b == new_ballot && state.prepared || MapSet.new(),
          pending: %{
            message: {:start_accept, new_ballot},
            until: fn s -> quorum(MapSet.size(s.prepared), s.neighbours) end
          }
        }

      # when a prepare method has been recieved send back prepared plus previous ballot if there was one before
      {:prepare, leader, b} ->
          send(leader, {:prepared, state.name, b, state.b_old > 0 && {state.b_old, state.v_old} || {:none}})
          %{state | b: b}

      # when preapred recieved update state map
      {:prepared, sender, b, vote_old} ->
          state.b == b && %{state | prepared: MapSet.put(state.prepared, {vote_old, sender})} || state

      # start accept phase
      {:start_accept, b} ->
        {max_ballot, sender} = Enum.max(MapSet.to_list(state.prepared))
        # find if a ballot is higher elsewhere
        v = max_ballot != {:none} && elem(max_ballot, 1) || state.v
        # broadcast
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
	#    IO.puts('sending accept')
            pid -> send(pid,  {:accept,self(), b,v})
          end
        end
        # same as above
        %{state |
          prepared: MapSet.new(),
          accepted: state.b == b && state.accepted || MapSet.new(),
          pending: %{
            message: {:start_decided, b},
            until: fn s -> quorum(MapSet.size(s.accepted), s.neighbours) end
          }
        }

      # send accepted message back to leader
      {:accept, leader, b, v} ->
  #	IO.puts('accepting')
          send(leader, {:accepted, state.name, b})
          %{state | b_old: b, v_old: v}

        #update state map based on accepts
      {:accepted, sender, b} ->
        state.b == b && %{state | accepted: MapSet.put(state.accepted, sender)} || state

        # start decided phase  - broadcasts decide
      {:start_decided, b} ->
#	IO.puts('decided')
        for p <- state.neighbours do
          case :global.whereis_name(p) do
            :undefined -> :undefined
            pid -> send(pid, {:decided,self(), state.v_old})
          end
        end
        %{state | accepted: MapSet.new()}

        # on decided
      {:decided, leader, v} ->
#	IO.puts('value decided')
        send(state.upper_layer, {:decide, v})
        %{state | b: 0, accepted: MapSet.new(), prepared: MapSet.new()}

        # after one second check if we're waiting for a message 
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
