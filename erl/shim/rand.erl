%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% rand: OTP's rand module for a program packed for the board, which takes
%% what it calls of this by reach. The numbers are the P2's hardware
%% generator's, p2:rnd/0, which keeps no state and takes no seed: seed/1 with
%% an algorithm's name, which seeds OTP's from the system's entropy, is
%% accepted and answers the name, and a seed of one's own, for a sequence
%% that repeats, is not there. An argument out of range fails with
%% function_clause, as OTP's does. Never on erl's path, where it would hide
%% OTP's own.
-module(rand).
-export([bytes/1, seed/1, uniform/0, uniform/1, uniform_real/0]).

seed(Alg) when is_atom(Alg) -> Alg.

%% uniform/0 is 0.0 =< X < 1.0 and uniform_real/0 0.0 < X < 1.0, both in
%% steps of 2^-24, which the VM's 32-bit floats hold exactly.
uniform() -> (p2:rnd() bsr 8) / 16777216.

uniform_real() -> ((p2:rnd() bsr 9) * 2 + 1) / 16777216.

uniform(N) when is_integer(N), N >= 1, N =< 16#100000000 -> p2:rnd() rem N + 1;
uniform(N) when is_integer(N), N >= 1 -> ((p2:rnd() band 16#3fffffff) bsl 32 bor p2:rnd()) rem N + 1.

bytes(N) when is_integer(N), N >= 0 -> list_to_binary(bytes(N, [])).

bytes(0, Acc) -> Acc;
bytes(N, Acc) -> bytes(N - 1, [p2:rnd() band 255 | Acc]).
