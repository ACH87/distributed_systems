defmodule SRS do

  def start(name, neighbours) do
    spawn(SRS, :init, [name, neighbours])
  end

  # neighbours are a list of process names
  def init(name, seats, num_of_seats) do

    # create a list of seats,
    seats = Map.new()
    # each process is a pid

    for seat <- 1..num_of_seats do
      layer = []
      for p <- seats do
        pid = Paxos.start('{seat}{p}', seats, self(())
        seats = layer + [pid]
      end
      Map.put(seat, layer, false)
    end )
    state = %{
      name: name,
      seats: seats
    }
    run(state)
  end

  def reserve_seat(seat, value) do
    send(self(), {:reserve_seat, seat, value})
  end

  defp run(state) do
    my_pid = self()
    my_name = state.name
    
    state = receive do
      {:reserve_seat, seat, value} ->
        seat_layer = state.seats.seat
        Paxos.propose(seat, value)
        Paxos.start_ballot(seat)
        leader = :rand.uniform(length(seat_layer))
        seat_pid = '{seat}{leader}'
        state = MapSet.put(state, {seat_layer.seat_pid, seat})
        state

      {:decided, sender, value} ->
        seat = state.sender
        state = %{state | seat: true}
        state


    end
    run(state)
  end

end
