%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% hello: the README's first program.
-module(hello).
-export([main/0]).

main() ->
    io:format("Hello, world!~n").
