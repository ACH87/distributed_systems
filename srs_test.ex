defmodule testcases do

  IEx.Helpers.c "srs.ex"


  def test_seat_reseve do

    srs = %{
      s0: [:p0, :p1, :p2],
      s1: [:p3, :p4, :p5],
      s2: [:p6, :p7, :p8, :p9, :p10]

    }

    SRS.start('srs1', srs, self())

    value = :random.uniform(10000000)

    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, 's1', value)
    end

    receive do
      {:reserved, v} ->
        IO.puts("#{'person reserved seat'}, #{v}")
    end
  end

  def test_concurrent_seat do
    srs = %{
      s0: [:p0, :p1, :p2],
      s1: [:p3, :p4, :p5],
      s2: [:p6, :p7, :p8, :p9, :p10]

    }

    SRS.start('srs1', srs, self())

    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, 's1', value)
    end

    case :global.whereis_name('srs1') do
      :undefined -> :undefined
      pid ->  SRS.reseve_seat(pid, 's2', value)
    end

    receive do
      {:reserved, seat, v} ->
        IO.puts("#{'person reserved seat'}, #{seat}, #{v}")
    end

    receive do
      {:reserved, seat, v} ->
        IO.puts("#{'person reserved'}, #{seat} #{v}")
    end

  end



end
