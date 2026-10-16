%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% links: links and exit signals, monitors, and registered names. The workers
%% end with exit, which erl does not log; a crash it would, and the logger's
%% report is not what a test can compare.
-module(links).
-export([main/0, worker/1, server/0]).

worker(Reason) ->
    receive
        go -> exit(Reason)
    end.

server() ->
    receive
        {From, Ref, Req} ->
            From ! {Ref, {answer, Req}},
            server()
    end.

main() ->
    process_flag(trap_exit, true),

    %% A linked worker that shuts down, one that exits with a reason, and one
    %% killed.
    W1 = spawn_link(?MODULE, worker, [shutdown]),
    W2 = spawn_link(?MODULE, worker, [boom]),
    W3 = spawn_link(?MODULE, worker, [never]),
    W1 ! go,
    W2 ! go,
    exit(W3, kill),
    io:format("~w~n", [[reason(W) || W <- [W1, W2, W3]]]),

    %% A link to a process that is gone, trapping exits: a signal of noproc.
    link(W1),
    io:format("~w~n", [reason(W1)]),

    %% A monitor: a normal end, then a monitor on a process that is gone. The
    %% worker waits to be told, so that the monitor is on it before it ends.
    W4 = spawn(fun() -> receive go -> ok end end),
    Ref = monitor(process, W4),
    W4 ! go,
    io:format("~w~n", [down(Ref, W4)]),
    Ref2 = monitor(process, W4),
    io:format("~w~n", [down(Ref2, W4)]),

    %% A registered server, called by name.
    S = spawn(?MODULE, server, []),
    true = register(answers, S),
    io:format("~w ~w~n", [whereis(answers) =:= S, whereis(nobody)]),
    R = make_ref(),
    answers ! {self(), R, 42},
    receive
        {R, Answer} -> io:format("~w~n", [Answer])
    end,
    exit(S, kill),
    receive
    after 10 -> ok
    end,
    io:format("~w ~w~n", [whereis(answers), is_process_alive(S)]),

    %% Unlinked, a worker's exit is not seen.
    W5 = spawn_link(?MODULE, worker, [quiet]),
    unlink(W5),
    W5 ! go,
    receive
        {'EXIT', W5, _} -> io:format("seen~n")
    after 20 -> io:format("not seen~n")
    end,
    io:format("~w~n", [catch exit(self(), stop)]),
    io:format("done~n").

reason(W) ->
    receive
        {'EXIT', W, Reason} -> Reason
    end.

down(Ref, W) ->
    receive
        {'DOWN', Ref, process, W, Reason} -> Reason
    end.
