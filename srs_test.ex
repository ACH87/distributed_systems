defmodule Testcases do

  IEx.Helpers.c "srs.ex"

  def init() do
    IO.puts('init')
  end

  # test seat reservation
  def test_seat_reseve() do

    srs = %{
      s0: ['p0', 'p1', 'p2'],
      s1: ['p3', 'p4', 'p5'],
      s2: ['p6', 'p7', 'p8', 'p9', 'p10']

    }
    SRS.start('srs1', srs, self())
    value = :rand.uniform(10000000)
    leader = :random.uniform(length(srs.s1)-1)
    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, :s1, value, leader)
    end


    receive do
      {:reserved,name, v} ->
        IO.puts("#{'person reserved seat'}, #{v}")
    end
  end

  # test availabilty
  def test_reservation() do
    srs = %{
      s0: ['p0', 'p1', 'p2'],
      s1: ['p3', 'p4', 'p5'],
      s2: ['p6', 'p7', 'p8', 'p9', 'p10']

    }
    SRS.start('srs1', srs, self())
    value = :rand.uniform(10000000)
    leader = :random.uniform(length(srs.s1)-1)
    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, :s1, value, leader)
    end


    receive do
      {:reserved,name, v} ->
        IO.puts("#{'person reserved seat'}, #{v}")
        case :global.whereis_name('srs1') do
          :undefined -> :undefined
          pid ->  SRS.check_available(pid, self(), :s1)
          receive do
            {:status, avilability} ->
              if avilability == :occupied do
                IO.puts('successful')
              end
          end
        end

    end
  end

  # test concurrent seat
  def test_concurrent_seat() do
    srs = %{
      s0: [:p0, :p1, :p2],
      s1: [:p3, :p4, :p5],
      s2: [:p6, :p7, :p8, :p9, :p10]

    }

    SRS.start('srs1', srs, self())


    value = :rand.uniform(10000000)

    leader = :random.uniform(length(srs.s1)-1)

    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, :s1, value, leader)
    end


    value = :rand.uniform(10000000)

    leader = :random.uniform(length(srs.s1)-1)

    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, :s1, value, leader)
    end

    receive do
      {:reserved, seat, v} ->
        IO.puts("#{'person reserved seat'}, #{seat}, #{v}")
    end

    # receive do
    #   {:reserved, seat, v} ->
    #     IO.puts("#{'person reserved'}, #{seat} #{v}")
    # end

  end



end
