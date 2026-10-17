%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erlang: the functions of OTP's erlang module that the VM has no BIF for
%% and that Erlang can write, for a program packed for the board, which takes
%% what it calls of this by reach. A call of erlang:F/A goes to the VM's BIF
%% when there is one and here otherwise; the guard BIFs (node/0, ceil/1,
%% floor/1 and the like) cannot come here, since a guard calls no function.
%% Never on erl's path, where it would hide OTP's own.
-module(erlang).
-compile({no_auto_import, [binary_to_integer/1, binary_to_integer/2,
                           binary_to_list/3, error/3, garbage_collect/0,
                           integer_to_binary/2, integer_to_list/2,
                           iolist_size/1, is_alive/0, list_to_integer/2,
                           nodes/0, spawn_monitor/1, spawn_monitor/3,
                           tuple_to_list/1]}).
-export([binary_to_integer/1, binary_to_integer/2, binary_to_list/3,
         convert_time_unit/3, error/3, garbage_collect/0,
         integer_to_binary/2, integer_to_list/2, iolist_size/1, is_alive/0,
         list_to_integer/2, nodes/0, send/3, spawn_monitor/1,
         spawn_monitor/3, tuple_to_list/1, yield/0]).

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
