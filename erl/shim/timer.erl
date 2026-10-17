%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% timer: OTP's timer module for a program packed for the board, which takes
%% what it calls of this by reach. OTP's one-shot timers live in a timer
%% server and its interval timers in a process each; here every timer is a
%% process of its own, which cancel/1 stops and waits for, so that a timer
%% cancelled does not fire after. An interval timer watches the process it
%% works for, as OTP's does, and ends with it. A destination {Name, Node} is
%% refused with {error, badarg}: the board is no node. Never on erl's path,
%% where it would hide OTP's own.
-module(timer).
-export([apply_after/2, apply_after/3, apply_after/4, apply_interval/2,
         apply_interval/3, apply_interval/4, apply_repeatedly/2,
         apply_repeatedly/3, apply_repeatedly/4, cancel/1, exit_after/2,
         exit_after/3, hms/3, hours/1, kill_after/1, kill_after/2,
         minutes/1, now_diff/2, seconds/1, send_after/2, send_after/3,
         send_interval/2, send_interval/3, sleep/1, start/0, tc/1, tc/2,
         tc/3, tc/4]).

-define(valid_time(T), is_integer(T), T >= 0).

apply_after(Time, F) when is_function(F, 0) -> apply_after(Time, erlang, apply, [F, []]);
apply_after(_, _) -> {error, badarg}.

apply_after(Time, F, A) when is_list(A), is_function(F, length(A)) ->
    apply_after(Time, erlang, apply, [F, A]);
apply_after(_, _, _) -> {error, badarg}.

apply_after(0, M, F, A) when is_atom(M), is_atom(F), is_list(A) ->
    _ = act({M, F, A}),
    {ok, {instant, make_ref()}};
apply_after(Time, M, F, A) when ?valid_time(Time), is_atom(M), is_atom(F), is_list(A) ->
    {ok, {once, once(Time, {M, F, A})}};
apply_after(_, _, _, _) -> {error, badarg}.

send_after(0, Dest, Msg) when is_pid(Dest); is_atom(Dest) ->
    Dest ! Msg,
    {ok, {instant, make_ref()}};
send_after(Time, Dest, Msg) when ?valid_time(Time), is_pid(Dest) ->
    {ok, {send_local, once(Time, {send, Dest, Msg})}};
send_after(Time, Dest, Msg) when ?valid_time(Time), is_atom(Dest) ->
    {ok, {once, once(Time, {send, Dest, Msg})}};
send_after(_, _, _) -> {error, badarg}.

send_after(Time, Msg) -> send_after(Time, self(), Msg).

exit_after(Time, Pid, Reason) -> apply_after(Time, erlang, exit, [Pid, Reason]).

exit_after(Time, Reason) -> exit_after(Time, self(), Reason).

kill_after(Time, Pid) -> exit_after(Time, Pid, kill).

kill_after(Time) -> exit_after(Time, self(), kill).

apply_interval(Time, F) when is_function(F, 0) -> apply_interval(Time, erlang, apply, [F, []]);
apply_interval(_, _) -> {error, badarg}.

apply_interval(Time, F, A) when is_list(A), is_function(F, length(A)) ->
    apply_interval(Time, erlang, apply, [F, A]);
apply_interval(_, _, _) -> {error, badarg}.

apply_interval(Time, M, F, A) when ?valid_time(Time), is_atom(M), is_atom(F), is_list(A) ->
    interval(Time, self(), {M, F, A}, false);
apply_interval(_, _, _, _) -> {error, badarg}.

apply_repeatedly(Time, F) when is_function(F, 0) -> apply_repeatedly(Time, erlang, apply, [F, []]);
apply_repeatedly(_, _) -> {error, badarg}.

apply_repeatedly(Time, F, A) when is_list(A), is_function(F, length(A)) ->
    apply_repeatedly(Time, erlang, apply, [F, A]);
apply_repeatedly(_, _, _) -> {error, badarg}.

apply_repeatedly(Time, M, F, A) when ?valid_time(Time), is_atom(M), is_atom(F), is_list(A) ->
    interval(Time, self(), {M, F, A}, true);
apply_repeatedly(_, _, _, _) -> {error, badarg}.

send_interval(Time, Dest, Msg) when ?valid_time(Time), is_pid(Dest) ->
    interval(Time, Dest, {send, Dest, Msg}, false);
send_interval(Time, Dest, Msg) when ?valid_time(Time), is_atom(Dest) ->
    interval(Time, whereis(Dest), {send, Dest, Msg}, false);
send_interval(_, _, _) -> {error, badarg}.

send_interval(Time, Msg) -> send_interval(Time, self(), Msg).

cancel({instant, Ref}) when is_reference(Ref) -> {ok, cancel};
cancel({Kind, Pid}) when is_pid(Pid), Kind =:= once orelse Kind =:= send_local orelse Kind =:= interval ->
    Ref = monitor(process, Pid),
    Pid ! {cancel, Pid},
    receive
        {'DOWN', Ref, process, _, _} -> {ok, cancel}
    end;
cancel(_) -> {error, badarg}.

%% once starts a one-shot timer, a process that does its action after Time
%% milliseconds unless it is cancelled first.
once(Time, Action) ->
    spawn(fun() ->
                  Self = self(),
                  receive
                      {cancel, Self} -> ok
                  after Time ->
                          _ = act(Action),
                          ok
                  end
          end).

%% interval starts an interval timer, a process that does its action every
%% Time milliseconds from now, as long as Target lives; with Wait, a spawned
%% action is waited for before the next is due, and one overdue is done at
%% once.
interval(Time, Target, Action, Wait) ->
    Due = erlang:monotonic_time(millisecond) + Time,
    Pid = spawn(fun() ->
                        case Target of
                            undefined -> ok;
                            _ -> tick(Due, Time, monitor(process, Target), Action, Wait)
                        end
                end),
    {ok, {interval, Pid}}.

tick(Due, Time, Mon, Action, Wait) ->
    Self = self(),
    receive
        {cancel, Self} -> ok;
        {'DOWN', Mon, process, _, _} -> ok
    after max(0, Due - erlang:monotonic_time(millisecond)) ->
            case act(Action) of
                {spawned, Pid} when Wait ->
                    Ref = monitor(process, Pid),
                    receive
                        {cancel, Self} -> ok;
                        {'DOWN', Mon, process, _, _} -> ok;
                        {'DOWN', Ref, process, _, _} -> tick(Due + Time, Time, Mon, Action, Wait)
                    end;
                _ ->
                    tick(Due + Time, Time, Mon, Action, Wait)
            end
    end.

%% act does a timer's action: a send or an exit signal by the timer itself,
%% anything else in a process of its own.
act({send, Dest, Msg}) ->
    catch Dest ! Msg;
act({erlang, exit, [Name, Reason]}) ->
    catch exit(pid(Name), Reason);
act({erlang, apply, [F, A]}) ->
    {spawned, spawn(fun() -> apply(F, A) end)};
act({M, F, A}) ->
    {spawned, spawn(fun() -> apply(M, F, A) end)}.

pid(Name) when is_atom(Name) -> whereis(Name);
pid(Pid) -> Pid.

sleep(T) ->
    receive
    after T -> ok
    end.

tc(F) -> tc(F, microsecond).

tc(F, A) when is_list(A) -> tc(F, A, microsecond);
tc(F, Unit) ->
    T1 = erlang:monotonic_time(),
    V = F(),
    T2 = erlang:monotonic_time(),
    {erlang:convert_time_unit(T2 - T1, native, Unit), V}.

tc(M, F, A) when is_list(A) -> tc(M, F, A, microsecond);
tc(F, A, Unit) ->
    T1 = erlang:monotonic_time(),
    V = apply(F, A),
    T2 = erlang:monotonic_time(),
    {erlang:convert_time_unit(T2 - T1, native, Unit), V}.

tc(M, F, A, Unit) ->
    T1 = erlang:monotonic_time(),
    V = apply(M, F, A),
    T2 = erlang:monotonic_time(),
    {erlang:convert_time_unit(T2 - T1, native, Unit), V}.

now_diff({A2, B2, C2}, {A1, B1, C1}) ->
    ((A2 - A1) * 1000000 + B2 - B1) * 1000000 + C2 - C1.

seconds(S) -> 1000 * S.

minutes(M) -> 60000 * M.

hours(H) -> 3600000 * H.

hms(H, M, S) -> hours(H) + minutes(M) + seconds(S).

%% There is no timer server to start.
start() -> ok.
