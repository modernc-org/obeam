%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% os: the time of OTP's os module, for a program packed for the board, which
%% takes what it calls of this by reach. The board has no calendar's clock:
%% the time is erlang:system_time's, the time since the board started. Never
%% on erl's path, where it would hide OTP's own.
-module(os).
-export([system_time/0, system_time/1, timestamp/0]).

system_time() -> erlang:system_time().

system_time(Unit) ->
    try erlang:system_time(Unit)
    catch
        error:badarg -> error(badarg, [Unit])
    end.

timestamp() -> erlang:timestamp().
