# seat
defmodule Seat do
  def start(name, participants, upper_layer) do

    if not Enum.member?(participants, name) do
      {:error, 'participants must contain member'}

    else
      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(Seat, :init, [name, participants, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> :error
        IO.puts('registed')
      end

    end
  end

  def reserve(pid, value) do
    send(self(), {pid, value})
  end

  def kill(pid) do
    send(self(), {'kill', pid})
  end

  #upper layer - the srs System
  #name - seat number -
  #participants - the paxos list ie [p1, p2, p3]
  def init( name, participants, upper_layer) do
    pids = for p <-participants do
      Paxos.start(p, participants, self())
    end
    state = %{
      srs: seat_reservation,
      name: name,
      participants: participants,
      avilability: :free
    }
    run(state)
  end

  def run(state) do
    receive do
      {:query, pid} ->
        send(pid, {:status, state.avilability})
        state

      {:reserve, sender, v} ->
        # start ballots
        if state.avilability do
          leader = :random.uniform(length(state.participants)-1)
          id = Enum.at(state.participants, leader)
          case :global.whereis_name(id) do
            Paxos.propose(id, v)
            Paxos.start_ballot(id)
            send(sender, {:started})
          end
        else
          send(pid, {state.avilability})
        end
        state

      {:decide, v} ->
        send(upper_layer, {:reserved, state.name, v})
        %{state | avilability: :occupied}
        state

      {:kill, pid} ->
        case :global.whereis_name(pid) do
          id -> Process.exit(id, :kill)
        end

  end

  run(state)
end
