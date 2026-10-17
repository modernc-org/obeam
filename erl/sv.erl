%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% sv: supervisors on OTP's supervisor, which the board has as a shim,
%% erl/shim/supervisor.erl, held here to the real one: one_for_one,
%% one_for_all, rest_for_one and simple_one_for_one; permanent, transient
%% and temporary children; the children's API; the restart intensity; and a
%% supervisor's init that fails. The workers are gen_servers of svw.erl,
%% named by their ids.
-module(sv).
-behaviour(supervisor).
-export([main/0, init/1]).

main() ->
    process_flag(trap_exit, true),
    one_for_one(),
    strategy(one_for_all),
    strategy(rest_for_one),
    restarts(),
    dynamic(),
    failures().

one_for_one() ->
    {ok, Sup} = supervisor:start_link({local, sup1}, ?MODULE, {one_for_one, [w1, w2]}),
    io:format("one_for_one: ~w ~w~n", [ids(Sup), supervisor:count_children(Sup)]),
    W1 = whereis(w1),
    crash(w1),
    io:format("w1 restarted: ~w, alive: ~w~n", [whereis(w1) =/= W1, is_pid(whereis(w1))]),
    io:format("terminate w2: ~w, ~w~n", [supervisor:terminate_child(sup1, w2), ids(Sup)]),
    io:format("restart w2: ~w~n", [ok(supervisor:restart_child(sup1, w2))]),
    io:format("restart w2 again: ~w~n", [supervisor:restart_child(sup1, w2)]),
    io:format("delete w2 running: ~w~n", [supervisor:delete_child(sup1, w2)]),
    ok = supervisor:terminate_child(sup1, w2),
    io:format("delete w2: ~w, ~w~n", [supervisor:delete_child(sup1, w2), ids(Sup)]),
    io:format("delete w9: ~w~n", [supervisor:delete_child(sup1, w9)]),
    io:format("start w3: ~w~n", [ok(supervisor:start_child(sup1, spec(w3, transient)))]),
    io:format("start w3 again: ~w~n", [element(1, element(2, supervisor:start_child(sup1, spec(w3, transient))))]),
    io:format("start w4: ~w~n", [ok(supervisor:start_child(sup1, spec(w4, temporary)))]),
    svw:stop(w3),
    svw:stop(w4),
    receive after 50 -> ok end,
    io:format("after normal ends: ~w~n", [ids(Sup)]),
    stop(Sup).

strategy(Strategy) ->
    {ok, Sup} = supervisor:start_link(?MODULE, {Strategy, [a, b, c]}),
    Before = pids([a, b, c]),
    crash(b),
    After = pids([a, b, c]),
    io:format("~w: ~w~n", [Strategy, [X =/= Y || {X, Y} <- lists:zip(Before, After)]]),
    stop(Sup).

restarts() ->
    {ok, Sup} = supervisor:start_link(?MODULE, {one_for_one, [r1]}),
    crash(r1),
    io:format("one restart: ~w~n", [is_process_alive(Sup)]),
    crash(r1),
    receive {'EXIT', Sup, Reason} -> io:format("too many restarts: ~w~n", [Reason]) end,
    io:format("r1 gone: ~w~n", [whereis(r1)]).

dynamic() ->
    {ok, Sup} = supervisor:start_link(?MODULE, simple),
    {ok, P1} = supervisor:start_child(Sup, [d1]),
    {ok, _} = supervisor:start_child(Sup, [d2]),
    io:format("simple: ~w ~w~n", [length(supervisor:which_children(Sup)), supervisor:count_children(Sup)]),
    crash(d1),
    io:format("d1 restarted: ~w~n", [is_pid(whereis(d1)) andalso whereis(d1) =/= P1]),
    io:format("terminate d2: ~w, left ~w~n", [supervisor:terminate_child(Sup, whereis(d2)), length(supervisor:which_children(Sup))]),
    stop(Sup).

failures() ->
    io:format("init ignore: ~w~n", [supervisor:start_link(?MODULE, ignore)]),
    io:format("bad child: ~w~n", [supervisor:start_link(?MODULE, {one_for_one, [f1, fail]})]),
    receive {'EXIT', _, _} -> ok after 100 -> ok end,
    io:format("f1 stopped: ~w~n", [whereis(f1)]).

crash(Name) ->
    catch svw:crash(Name),
    receive after 50 -> ok end.

stop(Sup) ->
    unlink(Sup),
    Ref = erlang:monitor(process, Sup),
    exit(Sup, shutdown),
    receive {'DOWN', Ref, process, Sup, R} -> io:format("stopped: ~w~n", [R]) end.

ids(Sup) -> [{Id, is_pid(P)} || {Id, P, worker, _} <- supervisor:which_children(Sup)].

pids(Names) -> [whereis(N) || N <- Names].

ok({ok, P}) when is_pid(P) -> ok;
ok(Other) -> Other.

spec(Id, Restart) ->
    #{id => Id, start => {svw, start_link, [Id]}, restart => Restart, shutdown => 1000}.

%% The supervisors.
init({Strategy, Ids}) ->
    {ok, {#{strategy => Strategy, intensity => 1, period => 5}, [spec(Id, permanent) || Id <- Ids]}};
init(simple) ->
    {ok, {#{strategy => simple_one_for_one},
          [#{id => d, start => {svw, start_link, []}}]}};
init(ignore) ->
    ignore.
