%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% blink: the board demo, two pins blinking at two rates, a process each. The
%% p2 module is the board's, so this module compiles everywhere and runs on the
%% board only.
-module(blink).
-export([main/0, blinker/2]).

main() ->
    spawn(?MODULE, blinker, [56, 500]),
    spawn(?MODULE, blinker, [57, 333]),
    receive
        stop -> ok
    end.

blinker(Pin, Ms) ->
    p2:pin_toggle(Pin),
    receive
        stop -> p2:pin_low(Pin)
    after Ms ->
        blinker(Pin, Ms)
    end.
