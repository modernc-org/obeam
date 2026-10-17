%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% svw: the workers sv.erl supervises, gen_servers named by their ids; one
%% named fail does not start.
-module(svw).
-behaviour(gen_server).
-export([start_link/1, crash/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link(Id) -> gen_server:start_link({local, Id}, ?MODULE, Id, []).

crash(Id) -> gen_server:call(Id, crash).

stop(Id) -> gen_server:call(Id, stop).

init(fail) -> {stop, no};
init(Id) -> {ok, Id}.

handle_call(crash, _From, _Id) ->
    1 = length(id([]));
handle_call(stop, _From, Id) ->
    {stop, normal, ok, Id}.

handle_cast(_, Id) -> {noreply, Id}.

id(X) -> X.
