defmodule SRS do

  IEx.Helpers.c "seat.ex"
  IEx.Helpers.c "paxos_test.ex"
  IEx.Helpers.c "uuid.ex"

  # Replace with your own implementation source files
  #IEx.Helpers.c "beb.ex"
  IEx.Helpers.c "paxos.ex"

  def start(name, seats, upper_layer) do

    if not Enum.member?(participants, name) do
      {:error, 'participants must contain member'}

    else
      # initiate layer, takes in an atom, the namesassociated with eighbour process, and the upper layer pid
      # spawns the process running the layer algorithmic logic specifying the floodingbc
      pid = spawn(SRS, :init, [name, seat, upper_layer])
      :global.unregister_name(name)
      case :global.register_name(name, pid) do
        :yes -> pid
        :no  -> :error
        IO.puts('registed')
      end

    end
  end

  #ie reserve s1, with the value 10
  def reseve_seat(srs, seat, value) do
    send(srs, {:reserve, seat, value})
  end

  def check_available(srs, sender, seat) do
    send(srs, {:check_available, sender, seat})
  end

  def init(name, seats, upper_layer) do
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
      {:reserve, seat, value} ->
        # get the name of a seat
        s = Map.fetch(state.seats, seat)
        # finds pid
        case :global.whereis_name(s) do
          :undefined -> :undefined
          pid -> Seat.reserve(pid, value)
        end
        state

       {:check_available, sender, seat} ->
         s = Map.fetch(state.seats, seat)
         case :global.whereis_name(s) do
           :undefined -> :undefined
           pid -> Seat.check_reservation(pid, sender)
         end
         state

      {:reserved, name, v} ->
        send(state.upper_layer, {:reserved, name, v})

    end
  end

end
