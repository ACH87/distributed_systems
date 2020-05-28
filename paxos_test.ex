defmodule PaxosTest do
    # The functions implement 
    # the module specific testing logic
    defp init(name, participants, all \\ false) do
        cpid = TestHarness.wait_to_register(:coord, :global.whereis_name(:coord))
        pid = Paxos.start(name, participants, self)        
        TestHarness.wait_for(MapSet.new(participants), name, 
                        (if not all, do: length(participants)/2, 
                        else: length(participants)))
        {cpid, pid}
    end

    defp kill_paxos(pid, name) do
        Process.exit(pid, :kill)
        :global.unregister_name(name)
    end


    defp retry(_, _, 0), do: {:none, 0}
    defp retry(pid, timeout, attempts) do
        receive do
            {:decide, val} -> {val, attempts}
            after timeout -> 
                Paxos.start_ballot(pid)
                retry(pid, timeout, attempts - 1)
        end
    end

    # Test cases start from here

    # No failures, no concurrent ballots
    def run_simple(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name == (fn [h | _] -> h end).(participants), do: Paxos.start_ballot(pid)
                receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # No failures, 2 concurrent ballots
    def run_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name in (fn [h1, h2 | _] -> [h1, h2] end).(participants), do: Paxos.start_ballot(pid)
                receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # No failures, many concurrent ballots
    def run_simple_many(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                for _ <- 1..10 do
                    Process.sleep(Enum.random(1..10))
                    Paxos.start_ballot(pid)
                end
                receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # One non-leader process crashes, no concurrent ballots
    def run_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name == (leader = (fn [h | _] -> h end).(participants)), 
                        do: Paxos.start_ballot(pid)
                
                if name == (kill_p = hd(List.delete(participants, leader))) do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                    # IO.puts("KILLED #{kill_p}")
                end

                if name in List.delete(participants, kill_p)  do
                    receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                    end
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # Minority non-leader crashes, no concurrent ballots
    def run_minority_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name == (leader = (fn [h | _] -> h end).(participants)), 
                        do: Paxos.start_ballot(pid)
                

                to_kill = Enum.slice(List.delete(participants, leader), 
                    0, div(length(participants),2))

                if name in to_kill do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if not (name in to_kill)  do
                    receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                    end
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # Leader crashes, no concurrent ballots
    def run_leader_crash_simple(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name == (leader = (fn [h | _] -> h end).(participants)) do 
                    Paxos.start_ballot(pid)
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == hd(List.delete(participants, leader)) do
		    IO.puts('#{'name'},#{name}')
                    Process.sleep(10)
                    Paxos.start_ballot(pid)
                end

                if name != leader do
                    receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 10000 -> IO.puts("#{name}: No decision after 10 seconds")
                    end
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # Leader and some non-leaders crash, no concurrent ballots
    # Needs to be run with at least 5 process config
    def run_leader_crash_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                if name == (leader = (fn [h | _] -> h end).(participants)) do 
                    Paxos.start_ballot(pid)
                    Process.sleep(Enum.random(1..5))
		    IO.puts('#{'killing'},#{name}')
                    Process.exit(pid, :kill)
                end

                spare = Enum.reduce(List.delete(participants, leader), List.delete(participants, leader), 
                    fn x, s -> if length(s) > length(participants) / 2 + 1, do: tl(s), else: s
                    end
                )

                IO.puts "leader, spare = #{leader}, #{inspect spare}"

                if not name in spare do
		    IO.puts('#{'killing name'},#{name}') 
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == hd(spare) do
                    Process.sleep(10)
		    IO.puts('#{'name'},#{name}')
                    Paxos.start_ballot(pid)
                end

                if name in spare do
                    receive do
                        {:decide, val} -> IO.puts("#{name}: decided #{inspect val}")
                        after 30000 -> IO.puts("#{name}: No decision after 30 seconds")
                    end
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end
end
