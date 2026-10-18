%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erlang: the functions of OTP's erlang module that the VM has no BIF for
%% and that Erlang can write, for a program packed for the board, which takes
%% what it calls of this by reach. A call of erlang:F/A goes to the VM's BIF
%% when there is one and here otherwise; what the compiler makes an
%% instruction of (node/0, ceil/1, floor/1, get/1 and the like) cannot come
%% here, an instruction calling no function. erlang:'$dict'/1 and
%% erlang:'$float'/2 are the VM's, for the process dictionary and
%% list_to_float/1. Never on erl's path, where it would hide OTP's own.
-module(erlang).
-compile({no_auto_import, [binary_to_existing_atom/1,
                           binary_to_existing_atom/2, binary_to_float/1,
                           binary_to_integer/1, binary_to_integer/2,
                           binary_to_list/3, erase/0, erase/1, error/3,
                           float_to_binary/1, float_to_binary/2,
                           float_to_list/1, float_to_list/2,
                           garbage_collect/0, get/0, get_keys/0, get_keys/1,
                           halt/0, halt/2, integer_to_binary/2,
                           integer_to_list/2, iolist_size/1, is_alive/0,
                           list_to_float/1, list_to_integer/2, nodes/0, put/2,
                           spawn_monitor/1, spawn_monitor/3, tuple_to_list/1]}).
-export([binary_to_existing_atom/1, binary_to_existing_atom/2,
         binary_to_float/1, binary_to_integer/1, binary_to_integer/2,
         binary_to_list/3, cancel_timer/1, cancel_timer/2,
         convert_time_unit/3, erase/0, erase/1, error/3, float_to_binary/1,
         float_to_binary/2, float_to_list/1, float_to_list/2,
         garbage_collect/0, get/0, get_keys/0, get_keys/1, halt/0, halt/2,
         integer_to_binary/2, integer_to_list/2, iolist_size/1, is_alive/0,
         list_to_float/1, list_to_integer/2, nodes/0, put/2, read_timer/1,
         read_timer/2,
         send/3, send_after/3, send_after/4, spawn_monitor/1,
         spawn_monitor/3, start_timer/3, start_timer/4, tuple_to_list/1,
         yield/0]).

tuple_to_list(T) when is_tuple(T) -> tuple_to_list(T, tuple_size(T), []);
tuple_to_list(T) -> error(badarg, [T]).

tuple_to_list(_, 0, Acc) -> Acc;
tuple_to_list(T, N, Acc) -> tuple_to_list(T, N - 1, [element(N, T) | Acc]).

%% spawn_monitor/1 and /3 hold the new process until the monitor is there,
%% so that a process ending at once is reported with its own reason, not
%% noproc: nothing but its parent knows it before the parent returns.
spawn_monitor(F) when is_function(F, 0) ->
    gate(spawn(fun() -> receive '$obeam_go' -> F() end end));
spawn_monitor(F) -> error(badarg, [F]).

spawn_monitor(M, F, A) when is_atom(M), is_atom(F), is_list(A) ->
    gate(spawn(fun() -> receive '$obeam_go' -> apply(M, F, A) end end));
spawn_monitor(M, F, A) -> error(badarg, [M, F, A]).

gate(Pid) ->
    Ref = monitor(process, Pid),
    Pid ! '$obeam_go',
    {Pid, Ref}.

%% The board is no node of a distributed system.
is_alive() -> false.

nodes() -> [].

send(Dest, Msg, Opts) when is_list(Opts) ->
    Dest ! Msg,
    ok;
send(Dest, Msg, Opts) -> error(badarg, [Dest, Msg, Opts]).

%% The VM collects a process's heap when it fills, and yields at calls.
garbage_collect() -> true.

yield() -> true.

error(Reason, Args, _Options) -> error(Reason, Args).

integer_to_list(I, Base) when is_integer(I), is_integer(Base), Base >= 2, Base =< 36 ->
    if
        I < 0 -> [$- | digits(-I, Base, [])];
        true -> digits(I, Base, [])
    end;
integer_to_list(I, Base) -> error(badarg, [I, Base]).

digits(I, Base, Acc) when I < Base -> [digit(I) | Acc];
digits(I, Base, Acc) -> digits(I div Base, Base, [digit(I rem Base) | Acc]).

digit(D) when D < 10 -> $0 + D;
digit(D) -> $A + D - 10.

integer_to_binary(I, Base) when is_integer(I), is_integer(Base), Base >= 2, Base =< 36 ->
    list_to_binary(integer_to_list(I, Base));
integer_to_binary(I, Base) -> error(badarg, [I, Base]).

list_to_integer(L, Base) when is_list(L), is_integer(Base), Base >= 2, Base =< 36 ->
    case parse(L, Base) of
        error -> error(badarg, [L, Base]);
        N -> N
    end;
list_to_integer(L, Base) -> error(badarg, [L, Base]).

binary_to_integer(B) when is_binary(B) ->
    case parse(binary_to_list(B), 10) of
        error -> error(badarg, [B]);
        N -> N
    end;
binary_to_integer(B) -> error(badarg, [B]).

binary_to_integer(B, Base) when is_binary(B), is_integer(Base), Base >= 2, Base =< 36 ->
    case parse(binary_to_list(B), Base) of
        error -> error(badarg, [B, Base]);
        N -> N
    end;
binary_to_integer(B, Base) -> error(badarg, [B, Base]).

parse([$- | L], Base) ->
    case unsigned(L, Base) of
        error -> error;
        N -> -N
    end;
parse([$+ | L], Base) -> unsigned(L, Base);
parse(L, Base) -> unsigned(L, Base).

unsigned([_ | _] = L, Base) -> parse(L, Base, 0);
unsigned(_, _) -> error.

parse([], _, N) -> N;
parse([C | L], Base, N) ->
    D = if
            C >= $0, C =< $9 -> C - $0;
            C >= $a, C =< $z -> C - $a + 10;
            C >= $A, C =< $Z -> C - $A + 10;
            true -> Base
        end,
    if
        D < Base -> parse(L, Base, N * Base + D);
        true -> error
    end;
parse(_, _, _) -> error.

binary_to_list(B, Start, Stop) when is_binary(B), is_integer(Start), is_integer(Stop),
                                    Start >= 1, Stop >= Start, Stop =< byte_size(B) ->
    take(Stop - Start + 1, drop(Start - 1, binary_to_list(B)), []);
binary_to_list(B, Start, Stop) -> error(badarg, [B, Start, Stop]).

drop(0, L) -> L;
drop(N, [_ | L]) -> drop(N - 1, L).

take(0, _, Acc) -> lists:reverse(Acc);
take(N, [C | L], Acc) -> take(N - 1, L, [C | Acc]).

iolist_size(L) ->
    case iosize(L, 0) of
        error -> error(badarg, [L]);
        N -> N
    end.

iosize([], N) -> N;
iosize(B, N) when is_binary(B) -> N + byte_size(B);
iosize([C | L], N) when is_integer(C), C >= 0, C =< 255 -> iosize(L, N + 1);
iosize([B | L], N) when is_binary(B) -> iosize(L, N + byte_size(B));
iosize([H | L], N) when is_list(H) ->
    case iosize(H, N) of
        error -> error;
        M -> iosize(L, M)
    end;
iosize(_, _) -> error.

convert_time_unit(T, From, To) when is_integer(T) ->
    case {per_second(From), per_second(To)} of
        {F, U} when is_integer(F), is_integer(U) ->
            if
                F =:= U -> T;
                F rem U =:= 0 -> floor_div(T, F div U);
                U rem F =:= 0 -> T * (U div F);
                true -> floor_div(T * U, F)
            end;
        _ -> error(badarg, [T, From, To])
    end;
convert_time_unit(T, From, To) -> error(badarg, [T, From, To]).

%% floor_div is A div B rounded down, as OTP rounds a conversion.
floor_div(A, B) when A >= 0 -> A div B;
floor_div(A, B) -> -((B - 1 - A) div B).

per_second(second) -> 1;
per_second(millisecond) -> 1000;
per_second(microsecond) -> 1000000;
per_second(nanosecond) -> 1000000000;
per_second(native) -> 1000000000;
per_second(perf_counter) -> 1000000000;
per_second(N) when is_integer(N), N > 0 -> N;
per_second(_) -> error.

%% The process dictionary: a map the VM keeps for each process, [] before the
%% first put, which erlang:'$dict'/1 replaces, answering the one that was
%% there. get/1, an instruction, is the VM's. get/0 and get_keys/0,1 answer
%% in the map's order, where OTP's are in its hash table's.
take() ->
    case erlang:'$dict'([]) of
        [] -> #{};
        D -> D
    end.

dict() ->
    D = take(),
    erlang:'$dict'(D),
    D.

put(K, V) ->
    D = take(),
    erlang:'$dict'(maps:put(K, V, D)),
    maps:get(K, D, undefined).

get() -> maps:to_list(dict()).

get_keys() -> maps:keys(dict()).

get_keys(V) -> [K || {K, X} <- maps:to_list(dict()), X =:= V].

erase() -> maps:to_list(take()).

erase(K) ->
    D = take(),
    case maps:find(K, D) of
        {ok, V} ->
            erlang:'$dict'(maps:remove(K, D)),
            V;
        error ->
            erlang:'$dict'(D),
            undefined
    end.

%% The timers of send_after/3,4 and start_timer/3,4: one process, which the
%% first timer starts and registers as '$obeam_timers', holds them in the
%% order they are due, {Due, Ref, Dest, Msg}, and sends each message when its
%% time comes, to a pid or to a name, which no process may have then. The
%% caller makes the reference, so that setting a timer waits for nothing;
%% cancel_timer/1,2 and read_timer/1,2 ask the process, which answers how
%% many milliseconds were left, or false. The times are the VM's
%% milliseconds, and a timer is not cancelled when its process ends.
send_after(T, Dest, Msg) -> send_after(T, Dest, Msg, []).

send_after(T, Dest, Msg, Opts) -> set_timer(T, Dest, Msg, Opts, false, [T, Dest, Msg, Opts]).

start_timer(T, Dest, Msg) -> start_timer(T, Dest, Msg, []).

start_timer(T, Dest, Msg, Opts) -> set_timer(T, Dest, Msg, Opts, true, [T, Dest, Msg, Opts]).

set_timer(T, Dest, Msg, Opts, Wrap, Args) when is_integer(T), is_list(Opts),
                                               (is_pid(Dest) orelse is_atom(Dest)) ->
    case timer_opts(Opts, [abs], #{abs => false}) of
        #{abs := Abs} when Abs orelse T >= 0 ->
            Ref = make_ref(),
            Due = if
                      Abs -> T;
                      true -> erlang:monotonic_time(millisecond) + T
                  end,
            M = if
                    Wrap -> {timeout, Ref, Msg};
                    true -> Msg
                end,
            timers() ! {set, Ref, Due, Dest, M},
            Ref;
        _ -> error(badarg, Args)
    end;
set_timer(_, _, _, _, _, Args) -> error(badarg, Args).

cancel_timer(Ref) -> cancel_timer(Ref, []).

cancel_timer(Ref, Opts) when is_reference(Ref), is_list(Opts) ->
    case timer_opts(Opts, [async, info], #{async => false, info => true}) of
        #{} = O -> timer_op(cancel, cancel_timer, Ref, O);
        bad -> error(badarg, [Ref, Opts])
    end;
cancel_timer(Ref, Opts) -> error(badarg, [Ref, Opts]).

read_timer(Ref) -> read_timer(Ref, []).

read_timer(Ref, Opts) when is_reference(Ref), is_list(Opts) ->
    case timer_opts(Opts, [async], #{async => false, info => true}) of
        #{} = O -> timer_op(read, read_timer, Ref, O);
        bad -> error(badarg, [Ref, Opts])
    end;
read_timer(Ref, Opts) -> error(badarg, [Ref, Opts]).

%% timer_opts reads options {Name, Boolean} of the names given into a map of
%% their defaults, or answers bad.
timer_opts([], _, O) -> O;
timer_opts([{K, V} | Os], Names, O) when is_boolean(V) ->
    case lists:member(K, Names) of
        true -> timer_opts(Os, Names, O#{K := V});
        false -> bad
    end;
timer_opts(_, _, _) -> bad.

%% timer_op cancels or reads a timer: what was left comes back as the answer,
%% or, with async, as the message {Tag, Ref, Left}; without info, ok, the
%% call waiting all the same unless it is async.
timer_op(Op, Tag, Ref, #{async := Async, info := Info}) ->
    Reply = if
                Async andalso Info -> Tag;
                Async -> none;
                true -> '$obeam_timer'
            end,
    case whereis('$obeam_timers') of
        undefined when Reply =:= none -> ok;
        undefined -> self() ! {Reply, Ref, false};
        P -> P ! {Op, Ref, self(), Reply}
    end,
    if
        Async -> ok;
        true ->
            receive
                {'$obeam_timer', Ref, Left} when Info -> Left;
                {'$obeam_timer', Ref, _} -> ok
            end
    end.

%% timers answers the timers' process, starting it if there is none: of two
%% processes starting it at once, the one whose register fails kills its own.
timers() ->
    case whereis('$obeam_timers') of
        undefined ->
            P = spawn(fun() -> timers([]) end),
            try register('$obeam_timers', P) of
                true -> P
            catch
                error:badarg ->
                    exit(P, kill),
                    timers()
            end;
        P -> P
    end.

timers(Ts) ->
    Now = erlang:monotonic_time(millisecond),
    case Ts of
        [{Due, _, Dest, Msg} | Rest] when Due =< Now ->
            _ = catch Dest ! Msg,
            timers(Rest);
        _ ->
            After = case Ts of
                        [] -> infinity;
                        [{Next, _, _, _} | _] -> Next - Now
                    end,
            receive
                {set, Ref, Due, Dest, Msg} ->
                    timers(insert({Due, Ref, Dest, Msg}, Ts));
                {Op, Ref, From, Reply} ->
                    {Left, Ts1} = find_timer(Op, Ref, Ts, Now, []),
                    if
                        Reply =:= none -> ok;
                        true -> From ! {Reply, Ref, Left}
                    end,
                    timers(Ts1)
            after After -> timers(Ts)
            end
    end.

%% insert puts a timer after those due no later, so that two set for the
%% same time go off in the order they were set.
insert(T, [U | Ts]) when element(1, U) =< element(1, T) -> [U | insert(T, Ts)];
insert(T, Ts) -> [T | Ts].

find_timer(_, _, [], _, Acc) -> {false, lists:reverse(Acc)};
find_timer(cancel, Ref, [{Due, Ref, _, _} | Ts], Now, Acc) ->
    {max(0, Due - Now), lists:reverse(Acc, Ts)};
find_timer(read, Ref, [{Due, Ref, _, _} | _] = Ts, Now, Acc) ->
    {max(0, Due - Now), lists:reverse(Acc, Ts)};
find_timer(Op, Ref, [T | Ts], Now, Acc) -> find_timer(Op, Ref, Ts, Now, [T | Acc]).

%% float_to_list/1,2 and float_to_binary/1,2, from the 21 significant digits
%% of float_to_list/1, which io_lib:format's ~.21e writes: decimals rounded
%% half up, and past 18 of them half to even, as OTP's are, compact,
%% scientific half to even, as C's printf rounds for OTP, and short as ~w
%% writes. Past the 21st digit they write 0s where OTP writes the exact
%% value's, and a tie is told from the 21 digits, where OTP rounds up to 18
%% decimals in floating point. A result is at most 255 characters, as OTP's.
float_to_list(F) -> float_to_list(F, []).

float_to_list(F, Opts) when is_float(F), is_list(Opts) ->
    L = case float_opts(Opts, {scientific, 20}, false) of
            {short, _} -> lists:flatten(io_lib:format("~w", [F]));
            {{decimals, D}, C} -> {decimals(F, D), C andalso D > 0};
            {{scientific, D}, _} -> scientific(F, D);
            bad -> bad
        end,
    case L of
        {Cs, true} when length(Cs) =< 255 -> compact(Cs);
        {Cs, false} when length(Cs) =< 255 -> Cs;
        [_ | _] when length(L) =< 255 -> L;
        _ -> error(badarg, [F, Opts])
    end;
float_to_list(F, Opts) -> error(badarg, [F, Opts]).

float_to_binary(F) -> float_to_binary(F, []).

float_to_binary(F, Opts) when is_float(F), is_list(Opts) ->
    try float_to_list(F, Opts) of
        L -> list_to_binary(L)
    catch
        error:badarg -> error(badarg, [F, Opts])
    end;
float_to_binary(F, Opts) -> error(badarg, [F, Opts]).

%% float_opts reads the options, the last of decimals, scientific and short
%% the one taken.
float_opts([], Form, C) -> {Form, C};
float_opts([{decimals, D} = Form | Os], _, C) when is_integer(D), D >= 0, D =< 253 ->
    float_opts(Os, Form, C);
float_opts([{scientific, D} = Form | Os], _, C) when is_integer(D), D >= 0, D =< 249 ->
    float_opts(Os, Form, C);
float_opts([short | Os], _, C) -> float_opts(Os, short, C);
float_opts([compact | Os], Form, _) -> float_opts(Os, Form, true);
float_opts(_, _, _) -> bad.

%% digits21 answers a float's 21 significant digits, the decimal exponent of
%% the first, and whether it is negative, -0.0 too.
digits21(F) ->
    case lists:flatten(io_lib:format("~.21e", [F])) of
        [$-, D, $. | Cs] -> digits21(Cs, true, [D]);
        [D, $. | Cs] -> digits21(Cs, false, [D])
    end.

digits21([$e | E], Neg, Ds) -> {Neg, lists:reverse(Ds), list_to_integer(E)};
digits21([C | Cs], Neg, Ds) -> digits21(Cs, Neg, [C | Ds]).

decimals(F, D) ->
    {Neg, Ds, E} = digits21(F),
    {I, Ds1} = if
                   E < 0 -> {1, lists:duplicate(-E, $0) ++ Ds};
                   true -> {E + 1, Ds}
               end,
    {Cs, I1} = case rounded(Ds1, I + D, D > 18) of
                   {M, true} -> {[$1 | M], I + 1};
                   {M, false} -> {M, I}
               end,
    {Whole, Frac} = lists:split(I1, Cs),
    sign(Neg, if
                  D > 0 -> Whole ++ [$. | Frac];
                  true -> Whole
              end).

%% compact drops the 0s that end the decimals, all but one.
compact(Cs) -> lists:reverse(uncompact(lists:reverse(Cs))).

uncompact([$0, C | Cs]) when C =/= $. -> uncompact([C | Cs]);
uncompact(Cs) -> Cs.

scientific(F, D) ->
    {Neg, Ds, E} = digits21(F),
    {[M | Ms], E1} = case rounded(Ds, D + 1, true) of
                         {Cs, true} -> {[$1 | lists:droplast(Cs)], E + 1};
                         {Cs, false} -> {Cs, E}
                     end,
    Point = case Ms of
                [] -> [];
                _ -> [$. | Ms]
            end,
    sign(Neg, [M | Point] ++ [$e | exponent(E1)]).

%% rounded answers the first N digits, 0s past the 21st, rounded on the rest,
%% half up, or half to even when Even is set, and whether that carried out of
%% the first: they are all 0s then.
rounded(Ds, N, Even) ->
    {Keep, Rest} = keep(N, Ds, []),
    case round_up(Rest, Keep, Even) of
        true -> carry(lists:reverse(Keep), []);
        false -> {Keep, false}
    end.

round_up([$5 | R], Keep, true) -> lists:any(fun(C) -> C =/= $0 end, R) orelse lists:last(Keep) rem 2 =:= 1;
round_up([C | _], _, _) -> C >= $5;
round_up([], _, _) -> false.

%% keep takes the first N digits, 0s past the 21st, and leaves the rest.
keep(0, Ds, Acc) -> {lists:reverse(Acc), Ds};
keep(N, [D | Ds], Acc) -> keep(N - 1, Ds, [D | Acc]);
keep(N, [], Acc) -> keep(N - 1, [], [$0 | Acc]).

%% carry adds one to the reversed digits.
carry([$9 | Ds], Acc) -> carry(Ds, [$0 | Acc]);
carry([D | Ds], Acc) -> {lists:reverse(Ds, [D + 1 | Acc]), false};
carry([], Acc) -> {Acc, true}.

exponent(E) when E < 0 -> [$- | two(-E)];
exponent(E) -> [$+ | two(E)].

two(E) when E < 10 -> [$0, $0 + E];
two(E) -> integer_to_list(E).

sign(true, Cs) -> [$- | Cs];
sign(false, Cs) -> Cs.

%% list_to_float/1 reads the syntax, Erlang's: a sign perhaps, digits, a
%% point and digits, and perhaps e or E, a sign perhaps and digits; the VM's
%% erlang:'$float'/2 the magnitude, from the significant digits, D, and k,
%% the value being 0.D times 10^k: the nearest 32-bit float, ties to even, or
%% badarg past the largest.
list_to_float(L) ->
    try
        {Neg, L1} = case L of
                        [$- | T] -> {true, T};
                        [$+ | T] -> {false, T};
                        _ -> {false, L}
                    end,
        {[_ | _] = W, [$. | L2]} = lists:splitwith(fun is_digit/1, L1),
        {[_ | _] = F, L3} = lists:splitwith(fun is_digit/1, L2),
        X = case L3 of
                [] -> 0;
                [C | Ex] when C =:= $e; C =:= $E -> read_exp(Ex)
            end,
        Ds = lists:dropwhile(fun(C) -> C =:= $0 end, W ++ F),
        Abs = erlang:'$float'(Ds, X - length(F) + length(Ds)),
        if
            Neg -> -Abs;
            true -> Abs
        end
    catch
        _:_ -> error(badarg, [L])
    end.

is_digit(C) -> is_integer(C) andalso C >= $0 andalso C =< $9.

%% read_exp reads an exponent, one of more than six digits as one past any
%% float's.
read_exp([$- | Ds]) -> -read_exp_digits(Ds);
read_exp([$+ | Ds]) -> read_exp_digits(Ds);
read_exp(Ds) -> read_exp_digits(Ds).

read_exp_digits([_ | _] = Ds) ->
    true = lists:all(fun is_digit/1, Ds),
    case lists:dropwhile(fun(C) -> C =:= $0 end, Ds) of
        [] -> 0;
        Sig when length(Sig) > 6 -> 999999;
        Sig -> list_to_integer(Sig)
    end.

binary_to_float(B) when is_binary(B) ->
    try list_to_float(binary_to_list(B))
    catch
        error:badarg -> error(badarg, [B])
    end;
binary_to_float(B) -> error(badarg, [B]).

%% halt/0 and halt/2 are halt/1, the VM's, which writes nothing more. The
%% options are not read.
halt() -> halt(0).

halt(Status, Opts) when is_list(Opts) -> halt(Status);
halt(Status, Opts) -> error(badarg, [Status, Opts]).

%% binary_to_existing_atom/1,2: the atom whose name the bytes are, in either
%% encoding, an atom's name being its bytes in the VM.
binary_to_existing_atom(B) -> binary_to_existing_atom(B, utf8).

binary_to_existing_atom(B, Enc) when is_binary(B), Enc =:= utf8 orelse Enc =:= unicode orelse Enc =:= latin1 ->
    try list_to_existing_atom(binary_to_list(B))
    catch
        error:badarg -> error(badarg, [B, Enc])
    end;
binary_to_existing_atom(B, Enc) -> error(badarg, [B, Enc]).
