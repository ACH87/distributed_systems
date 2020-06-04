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

  #upper layer - the srs System
  #name - seat number -
  #participants - the paxos
  def init( name, participants, upper_layer) do
    state = %{
      srs: seat_reservation,
      name: name,
      participants: participants,
      avilability: false
    }
    #TODO start each process
    run(state)
  end

  def run(state) do
    receive do
      {:query, pid} ->
        send(pid, {:avilability, state.avilability})
        state

      {:reserve, pid, v, s} ->
        # start ballots
        seat = Map.fetch(state.participants, s)
        seat.propose(v)
        seat.start_ballot()
        state

      {:decide, v} ->
        send(upper_layer, {:reserved, self(), v})
        %{state | avilability: true}

  end

  run(state)
end
