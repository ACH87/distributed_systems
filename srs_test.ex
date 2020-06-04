defmodule testcases do

  def test_seat_reseve do

    srs = %{
      s0: [:p0, :p1, :p2],
      s1: [:p3, :p4, :p5],
      s2: [:p6, :p7, :p8, :p9, :p10]

    }

    SRS.start('srs1', srs, self())

    value = :random.uniform(10000000)

    SRS.reseve_seat(self(), 's1', value)

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

    SRS.reseve_seat(self(), 's1')
    SRS.reseve_seat(self(), 's2')

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
