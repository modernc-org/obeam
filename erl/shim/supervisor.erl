%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% supervisor: OTP's supervisor, in Erlang over the VM's processes, for a
%% program packed for the board, which takes what it calls of this by reach.
%% Never on erl's path, where it would hide OTP's own.
%%
%% What a callback module meets is OTP's: start_link, named {local, Name} or
%% not; init/1 answering {ok, {Flags, ChildSpecs}} or ignore, the flags and
%% the specs as maps or as OTP's tuples; the strategies one_for_one,
%% one_for_all, rest_for_one and simple_one_for_one; permanent, transient
%% and temporary children, shut down by brutal_kill, a timeout or infinity;
%% the restart intensity, past which the supervisor shuts its children down
%% and ends with shutdown; start_child, terminate_child, restart_child,
%% delete_child, which_children and count_children. It is no gen_server
%% callback module, as OTP's is: a library is packed by reach, and the
%% callbacks gen_server calls by name would be left out; it answers
%% gen_server:call itself. A dynamic child of simple_one_for_one has its
%% first pid for an id. A child's start function is called by apply, so
%% it is to be the program's own, as OTP's examples have it, {Mod,
%% start_link, Args}: a shim's named there, {gen_server, start_link, ...},
%% is not packed. Not here: auto_shutdown and significant children, the
%% sys protocol, and the supervisor's reports, which the VM's own reports of
%% crashed processes stand for.
-module(supervisor).
-export([start_link/2, start_link/3, start_child/2, terminate_child/2,
         restart_child/2, delete_child/2, which_children/1, count_children/1]).

start_link(Mod, Args) -> start_it(nameless, Mod, Args).

start_link(Name, Mod, Args) -> start_it(Name, Mod, Args).

start_child(Sup, Spec) -> gen_server:call(Sup, {start_child, Spec}, infinity).
terminate_child(Sup, Id) -> gen_server:call(Sup, {terminate_child, Id}, infinity).
restart_child(Sup, Id) -> gen_server:call(Sup, {restart_child, Id}, infinity).
delete_child(Sup, Id) -> gen_server:call(Sup, {delete_child, Id}, infinity).
which_children(Sup) -> gen_server:call(Sup, which_children, infinity).
count_children(Sup) -> gen_server:call(Sup, count_children, infinity).

start_it(Name, Mod, Args) ->
    Starter = self(),
    Pid = spawn_link(fun() -> init_it(Starter, Name, Mod, Args) end),
    Mref = erlang:monitor(process, Pid),
    receive
        {'$sup_ack', Pid, Return} ->
            erlang:demonitor(Mref),
            receive {'DOWN', Mref, _, _, _} -> ok after 0 -> ok end,
            Return;
        {'DOWN', Mref, process, Pid, Reason} ->
            {error, Reason}
    end.

ack(Starter, Return) -> Starter ! {'$sup_ack', self(), Return}.

%% init_it is the supervisor's beginning: its name, init/1, and its children
%% started in their order.
init_it(Starter, Name, Mod, Args) ->
    process_flag(trap_exit, true),
    case register_name(Name) of
        {false, Pid} ->
            ack(Starter, {error, {already_started, Pid}});
        true ->
            case catch Mod:init(Args) of
                {ok, {Flags, Specs}} ->
                    init_children(Starter, flags(Flags), Specs);
                ignore ->
                    ack(Starter, ignore),
                    exit(normal);
                Other ->
                    Reason = {bad_return, {Mod, init, Other}},
                    ack(Starter, {error, Reason}),
                    exit(Reason)
            end
    end.

init_children(Starter, error, _) ->
    ack(Starter, {error, {supervisor_data, bad_flags}}),
    exit({supervisor_data, bad_flags});
init_children(Starter, Flags = #{strategy := simple_one_for_one}, [Spec]) ->
    case spec(Spec) of
        {ok, Template} ->
            ack(Starter, {ok, self()}),
            loop(Flags#{parent => Starter, template => Template, children => [], restarts => []});
        error ->
            bad_spec(Starter, Spec)
    end;
init_children(Starter, Flags, Specs) ->
    case specs(Specs, []) of
        {ok, Children} ->
            case start_all(lists:reverse(Children), []) of
                {ok, Started} ->
                    ack(Starter, {ok, self()}),
                    loop(Flags#{parent => Starter, children => Started, restarts => []});
                {error, Started, Id, Reason} ->
                    shutdown_all(Started),
                    R = {shutdown, {failed_to_start_child, Id, Reason}},
                    ack(Starter, {error, R}),
                    exit(R)
            end;
        {error, Spec} ->
            bad_spec(Starter, Spec)
    end.

bad_spec(Starter, Spec) ->
    R = {start_spec, {invalid_child_spec, Spec}},
    ack(Starter, {error, R}),
    exit(R).

register_name(nameless) -> true;
register_name({local, Name}) ->
    try register(Name, self()) of
        true -> true
    catch
        error:badarg -> {false, whereis(Name)}
    end.

flags(#{} = F) ->
    flags({maps:get(strategy, F, one_for_one), maps:get(intensity, F, 1), maps:get(period, F, 5)});
flags({Strategy, Intensity, Period}) when is_integer(Intensity), Intensity >= 0, is_integer(Period), Period > 0 ->
    case lists:member(Strategy, [one_for_one, one_for_all, rest_for_one, simple_one_for_one]) of
        true -> #{strategy => Strategy, intensity => Intensity, period => Period};
        false -> error
    end;
flags(_) -> error.

specs([], Acc) -> {ok, Acc};
specs([S | T], Acc) ->
    case spec(S) of
        {ok, C = #{id := Id}} ->
            case lists:any(fun(#{id := I}) -> I =:= Id end, Acc) of
                true -> {error, S};
                false -> specs(T, [C | Acc])
            end;
        error -> {error, S}
    end.

%% spec makes a child of a child spec, a map or OTP's tuple.
spec(#{id := Id, start := {M, F, A} = Start} = S) when is_atom(M), is_atom(F), is_list(A) ->
    Type = maps:get(type, S, worker),
    child(Id, Start, maps:get(restart, S, permanent), maps:get(shutdown, S, shutdown_default(Type)),
          Type, maps:get(modules, S, [M]));
spec({Id, {M, F, A} = Start, Restart, Shutdown, Type, Modules}) when is_atom(M), is_atom(F), is_list(A) ->
    child(Id, Start, Restart, Shutdown, Type, Modules);
spec(_) -> error.

child(Id, Start, Restart, Shutdown, Type, Modules) ->
    Valid = lists:member(Restart, [permanent, transient, temporary]) andalso
        lists:member(Type, [worker, supervisor]) andalso
        (Shutdown =:= brutal_kill orelse Shutdown =:= infinity orelse is_integer(Shutdown) andalso Shutdown >= 0),
    case Valid of
        true -> {ok, #{id => Id, start => Start, restart => Restart, shutdown => Shutdown,
                       type => Type, modules => Modules, pid => undefined}};
        false -> error
    end.

shutdown_default(worker) -> 5000;
shutdown_default(_) -> infinity.

%% start_all starts children in their order, and answers them newest first,
%% or which one failed and the ones started before it.
start_all([], Acc) -> {ok, Acc};
start_all([C = #{id := Id} | T], Acc) ->
    case start(C) of
        {ok, C2} -> start_all(T, [C2 | Acc]);
        {error, Reason} -> {error, Acc, Id, Reason}
    end.

start(C = #{start := {M, F, A}}) ->
    case catch apply(M, F, A) of
        {ok, Pid} when is_pid(Pid) -> {ok, C#{pid := Pid}};
        {ok, Pid, _} when is_pid(Pid) -> {ok, C#{pid := Pid}};
        ignore -> {ok, C#{pid := undefined}};
        {error, Reason} -> {error, Reason};
        {'EXIT', Reason} -> {error, Reason};
        Other -> {error, Other}
    end.

shutdown_all(Children) ->
    lists:foreach(fun shutdown/1, Children).

shutdown(#{pid := undefined}) -> ok;
shutdown(#{pid := Pid, shutdown := Shutdown}) ->
    case Shutdown of
        brutal_kill ->
            exit(Pid, kill),
            receive {'EXIT', Pid, _} -> ok end;
        infinity ->
            exit(Pid, shutdown),
            receive {'EXIT', Pid, _} -> ok end;
        Ms ->
            exit(Pid, shutdown),
            receive
                {'EXIT', Pid, _} -> ok
            after Ms ->
                exit(Pid, kill),
                receive {'EXIT', Pid, _} -> ok end
            end
    end.

%% loop answers calls and sees its children end.
loop(S = #{parent := Parent}) ->
    receive
        {'EXIT', Parent, Reason} ->
            shutdown_all(maps:get(children, S)),
            exit(Reason);
        {'EXIT', Pid, Reason} ->
            loop(child_exit(Pid, Reason, S));
        {'$gen_call', From, Request} ->
            {Reply, S2} = call(Request, S),
            gen_server:reply(From, Reply),
            loop(S2);
        _ ->
            loop(S)
    end.

child_exit(Pid, Reason, S = #{children := Children}) ->
    case lists:partition(fun(#{pid := P}) -> P =:= Pid end, Children) of
        {[C], _} -> exited(C, Reason, S);
        {[], _} -> S
    end.

%% exited deals with a child's end. The child runs no more from here on, so
%% that a shutdown of the children, the intensity's, does not wait for its
%% 'EXIT', which has come.
exited(C0 = #{restart := Restart}, Reason, S0) ->
    C = C0#{pid := undefined},
    S = S0#{children := replace(C, maps:get(children, S0))},
    case restarts(Restart, Reason) of
        true ->
            restart(C, add_restart(S));
        false when Restart =:= temporary; map_get(strategy, S) =:= simple_one_for_one ->
            S#{children := remove(C, maps:get(children, S))};
        false ->
            S
    end.

restarts(permanent, _) -> true;
restarts(temporary, _) -> false;
restarts(transient, normal) -> false;
restarts(transient, shutdown) -> false;
restarts(transient, {shutdown, _}) -> false;
restarts(transient, _) -> true.

%% add_restart counts a restart, and shuts the supervisor down when there
%% have been more than the intensity within the period.
add_restart(S = #{intensity := I, period := P, restarts := Rs}) ->
    Now = erlang:monotonic_time(millisecond),
    Recent = [T || T <- [Now | Rs], Now - T < P * 1000],
    case length(Recent) > I of
        true ->
            shutdown_all(maps:get(children, S)),
            exit(shutdown);
        false ->
            S#{restarts := Recent}
    end.

restart(C = #{id := Id}, S = #{strategy := Strategy, children := Children}) ->
    case Strategy of
        one_for_all ->
            shutdown_all(Children),
            restart_in_order(lists:reverse(Children), [], S);
        rest_for_one ->
            {After, [Me | Before]} = lists:splitwith(fun(#{id := I}) -> I =/= Id end, Children),
            shutdown_all(After),
            restart_in_order([Me | lists:reverse(After)], Before, S);
        _ ->
            case start(C) of
                {ok, C2} -> S#{children := replace(C2, Children)};
                {error, _} -> restart(C, add_restart(S))
            end
    end.

%% restart_in_order starts the children in their order onto the ones
%% before them, newest first; one that fails is tried again, as a restart.
restart_in_order([], Acc, S) -> S#{children := Acc};
restart_in_order([C | T], Acc, S) ->
    case start(C) of
        {ok, C2} -> restart_in_order(T, [C2 | Acc], S);
        {error, _} -> restart_in_order([C | T], Acc, add_restart(S))
    end.

remove(#{id := Id}, Children) -> [C || C = #{id := I} <- Children, I =/= Id].

replace(C = #{id := Id}, Children) ->
    [case I of Id -> C; _ -> O end || O = #{id := I} <- Children].

find(Id, Children) ->
    case [C || C = #{id := I} <- Children, I =:= Id] of
        [C] -> {ok, C};
        [] -> error
    end.

%% call answers the supervisor's API.
call({start_child, Args}, S = #{strategy := simple_one_for_one, template := T}) ->
    #{start := {M, F, A}} = T,
    case start(T#{start := {M, F, A ++ Args}, id := undefined}) of
        {ok, C = #{pid := Pid}} when is_pid(Pid) -> {{ok, Pid}, S#{children := [C#{id := Pid} | maps:get(children, S)]}};
        {ok, _} -> {{ok, undefined}, S};
        {error, R} -> {{error, R}, S}
    end;
call({start_child, Spec}, S = #{children := Children}) ->
    case spec(Spec) of
        error ->
            {{error, {invalid_child_spec, Spec}}, S};
        {ok, C = #{id := Id}} ->
            case find(Id, Children) of
                {ok, #{pid := Pid}} when is_pid(Pid) -> {{error, {already_started, Pid}}, S};
                {ok, _} -> {{error, already_present}, S};
                error ->
                    case start(C) of
                        {ok, C2 = #{pid := Pid}} -> {{ok, Pid}, S#{children := [C2 | Children]}};
                        {error, R} -> {{error, R}, S}
                    end
            end
    end;
call({terminate_child, Pid}, S = #{strategy := simple_one_for_one, children := Children}) ->
    case [C || C = #{pid := P} <- Children, P =:= Pid, is_pid(Pid)] of
        [C] ->
            shutdown(C),
            {ok, S#{children := [O || O = #{pid := P} <- Children, P =/= Pid]}};
        [] ->
            {{error, not_found}, S}
    end;
call({terminate_child, Id}, S = #{children := Children}) ->
    case find(Id, Children) of
        {ok, C = #{restart := temporary}} ->
            shutdown(C),
            {ok, S#{children := remove(C, Children)}};
        {ok, C} ->
            shutdown(C),
            {ok, S#{children := replace(C#{pid := undefined}, Children)}};
        error ->
            {{error, not_found}, S}
    end;
call({restart_child, _}, S = #{strategy := simple_one_for_one}) ->
    {{error, simple_one_for_one}, S};
call({restart_child, Id}, S = #{children := Children}) ->
    case find(Id, Children) of
        {ok, #{pid := Pid}} when is_pid(Pid) -> {{error, running}, S};
        {ok, C} ->
            case start(C) of
                {ok, C2 = #{pid := Pid}} -> {{ok, Pid}, S#{children := replace(C2, Children)}};
                {error, R} -> {{error, R}, S}
            end;
        error -> {{error, not_found}, S}
    end;
call({delete_child, _}, S = #{strategy := simple_one_for_one}) ->
    {{error, simple_one_for_one}, S};
call({delete_child, Id}, S = #{children := Children}) ->
    case find(Id, Children) of
        {ok, #{pid := Pid}} when is_pid(Pid) -> {{error, running}, S};
        {ok, C} -> {ok, S#{children := remove(C, Children)}};
        error -> {{error, not_found}, S}
    end;
call(which_children, S = #{children := Children}) ->
    Dynamic = maps:get(strategy, S) =:= simple_one_for_one,
    {[{case Dynamic of true -> undefined; false -> Id end, Pid, Type, Mods}
      || #{id := Id, pid := Pid, type := Type, modules := Mods} <- Children], S};
call(count_children, S = #{children := Children}) ->
    Specs = case S of
                #{strategy := simple_one_for_one} -> 1;
                _ -> length(Children)
            end,
    Active = length([P || #{pid := P} <- Children, is_pid(P)]),
    Sups = length([T || #{type := T} <- Children, T =:= supervisor]),
    {[{specs, Specs}, {active, Active}, {supervisors, Sups}, {workers, length(Children) - Sups}], S};
call(_, S) ->
    {{error, badarg}, S}.
