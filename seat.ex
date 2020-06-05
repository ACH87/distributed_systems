# represents a seat which contains a paxos consensus layer
defmodule Seat do
  def start(name, participants, upper_layer) do


      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer (srs) pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(Seat, :init, [name, participants, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> IO.puts('did not register')
      end

  end

  #reserver a pid (seat)  with the value, p representing the leader ballot
  def reserve(pid, value, p) do
    send(pid, {:reserve, value, p})
  end

  #kill a seat - needed for test cases
  def kill(pid) do
    send(self(), {'kill', pid})
  end

  #pid = seat, sender = sender process
  def check_reservation(pid, sender) do
    send(pid, {:query, sender})
  end

  #upper layer - the srs System
  #name - seat number -
  #participants - the paxos list ie [p1, p2, p3]
  def init( name, participants, upper_layer) do
    # create a paxos consensus layer
    pids = for p <-participants do
      Paxos.start(p, participants, self())
    end
    state = %{
      name: name,
      participants: participants,
      upper_layer: upper_layer,
      counter: 0,
      avilability: :free
    }
    run(state)
  end

  def run(state) do
    receive do
      # check availabilty based on layer who requeted it
      {:query, pid} ->
        send(pid, {:status, state.avilability})
        state

        # v represents value, p is an int corresponding to a process
      {:reserve,  v, p} ->
        # start ballots
        if state.avilability == :free do
          # pick a random paxos instance to become the leader and start a ballot
          id = Enum.at(state.participants, p)
          case :global.whereis_name(id) do
            :undefined -> IO.puts('paxos undefined')
            pid -> Paxos.propose(pid,{:val, v})
            Paxos.start_ballot(pid)
            # send(sender, {:started})
          end
        else
          send(state.upper_layer, {state.avilability})
        end
        state
        # when a value has been decidedreport to srs
      {:decide, v} ->
        state = %{state | counter: state.counter+1}
        state = if state.counter == length(state.participants) do
          send(state.upper_layer, {:reserved, state.name, v})
          %{state | avilability: :occupied, counter: 0}
        else
          state
        end
        state

        # kill a paxos instance - use for testing
      {:kill, pid} ->
        case :global.whereis_name(pid) do
          id -> Process.exit(id, :kill)
        end

      end
    run(state)
  end

end
