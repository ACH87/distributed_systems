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


    defp retry(_, _, 0), do: {:none, {:none, 0}}
    defp retry(pid, timeout, attempts) do
        receive do
            {:decide, val} -> {:decide, {val, attempts}}
            after timeout -> 
                if pid != :none, do: Paxos.start_ballot(pid)
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
                lid = if name == hd(Enum.reverse(participants)), do: pid, else: :none
                {status, {val, a}} = retry(lid, 1000, 10)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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
                lid = if name == hd(Enum.reverse(participants)), do: pid, else: :none
                {status, {val, a}} = retry(lid, 1000, 10)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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
                {status, {val, a}} = retry(pid, 1000, 10)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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

                spare = List.delete(participants, kill_p)

                if name in  spare do
                    lid = if name == hd(Enum.reverse(spare)), do: pid, else: :none
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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

                spare = for p <- participants, not p in to_kill, do: p

                if name in spare do
                    lid = if name == hd(Enum.reverse(spare)), do: pid, else: :none
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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
                    Process.sleep(10)
                    Paxos.start_ballot(pid)
                end

                spare = List.delete(participants, leader)

                if name in spare do
                    lid = if name == hd(Enum.reverse(spare)), do: pid, else: :none
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
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
                    Process.exit(pid, :kill)
                end

                spare = Enum.reduce(List.delete(participants, leader), List.delete(participants, leader), 
                    fn x, s -> if length(s) > length(participants) / 2 + 1, do: tl(s), else: s
                    end
                )

                if not name in spare do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == hd(spare) do
                    Process.sleep(10)
                    Paxos.start_ballot(pid)
                end

                if name in spare do
                    lid = if name == hd(Enum.reverse spare), do: pid, else: :none
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # Cascading failures of leaders and non-leaders
    def run_leader_crash_complex(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                
                {kill, spare} = Enum.reduce(participants, {[], participants}, 
                    fn x, {k, s} -> if length(s) > length(participants) / 2 + 1, 
                        do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                    end
                )  

                leaders = Enum.slice(kill, 0, div(length(kill), 2))
                followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)
                
                # IO.puts("spare = #{inspect spare}")
                # IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                if name in leaders do
                    Paxos.start_ballot(pid)
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name in followers do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == hd(spare) do
                    Process.sleep(10)
                    Paxos.start_ballot(pid)
                end

                if name in spare do
                    # lid = if name == hd(Enum.reverse spare), do: pid, else: :none
                    lid = if name == (leader = hd(spare)), do: pid, else: :none
                    # IO.puts "#{name}: elected #{leader} to finish up"
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end

    # Cascading failures of leaders and non-leaders, random delays
    def run_leader_crash_complex_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        receive do
            :start -> 
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, val)
                
                {kill, spare} = Enum.reduce(participants, {[], participants}, 
                    fn x, {k, s} -> if length(s) > length(participants) / 2 + 1, 
                        do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                    end
                )  

                leaders = Enum.slice(kill, 0, div(length(kill), 2))
                followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)
                
                IO.puts("spare = #{inspect spare}")
                IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                if name in leaders do
                    Paxos.start_ballot(pid)
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name in followers do
                    for i <- 1..10 do
                        :erlang.suspend_process(pid)
                        Process.sleep(Enum.random(1..5))
                        :erlang.resume_process(pid)
                    end
                    Process.exit(pid, :kill)
                end

                if name == hd(spare) do
                    Process.sleep(10)
                    Paxos.start_ballot(pid)
                end

                if name in spare do
                    for i <- 1..10 do
                        :erlang.suspend_process(pid)
                        Process.sleep(Enum.random(1..5))
                        :erlang.resume_process(pid)
                        if name == hd(Enum.reverse spare), do: Paxos.start_ballot(pid)
                    end

                    lid = if name == hd(spare), do: pid, else: :none
                    # lid = if name == hd(Enum.reverse spare), do: pid, else: :none
                    {status, {val, a}} = retry(lid, 1000, 10)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val} after #{10 - a + 1} attempts"), 
                        else: IO.puts("#{name}: No decision after 10 seconds")
                end
        end
        send(cpid, :done)
        receive do
            :all_done -> 
                if name in spare, do:
                    IO.puts("#{name}: #{inspect Process.info(pid, :message_queue_len)}")
                kill_paxos(pid, name)
                send cpid, :finished
        end
    end
end