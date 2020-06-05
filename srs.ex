defmodule SRS do

  IEx.Helpers.c "seat.ex"
  IEx.Helpers.c "paxos_test.ex"
  IEx.Helpers.c "uuid.ex"

  # Replace with your own implementation source files
  #IEx.Helpers.c "beb.ex"
  IEx.Helpers.c "paxos_cw.ex"

  #name of srs, upper layer the application, seats -  a map of seats against a list of paxos' instances
  def start(name, seats, upper_layer) do

      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(SRS, :init, [name, seats, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> :error
      end

  end

  #ie reserve s1, with the value 10 and the value
  def reseve_seat(srs, seat, value, p) do
    send(srs, {:reserve, seat, value, p})
  end

  #check availability
  def check_available(srs, sender, seat) do
    IO.puts('checking ')
    send(srs, {:check_available, sender, seat})
  end

  def init(name, seats, upper_layer) do
    # create a seat
    for {n, participants} <- seats do
      create_seat(n, participants)
    end
    state = %{
      name: name,
      seats: seats,
      upper_layer: upper_layer
    }

    run(state)
  end

  # create participants for a seat
  def create_seat(name, participants) do
    Seat.start(name, participants, self())
  end

  def run(state) do

    receive do
      {:reserve, seat, value, p} ->
        # get the name of a seat
        # s = Map.fetch(state.seats, seat)
        # finds pid
        case :global.whereis_name(seat) do
          :undefined -> IO.puts('seat undefined')
          pid -> Seat.reserve(pid, value, p)
        end
        state

        # check availabilty for a seat
       {:check_available, sender, seat} ->
         case :global.whereis_name(seat) do
           :undefined -> :undefined
           pid -> Seat.check_reservation(pid, sender)
         end
         state

        #once a seat is reserved
      {:reserved, name, v} ->
        send(state.upper_layer, {:reserved, name, v})
        state

    end

    run(state)
  end

end
