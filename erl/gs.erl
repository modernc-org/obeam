%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% gs: a key-value server on OTP's gen_server, which the board has as a shim,
%% erl/shim/gen_server.erl, held here to the real one: start and start_link,
%% names, call and cast, info, timeouts and continue, a deferred reply, a
%% call that times out, init's other answers, a crash and what a caller and
%% the linked starter see of it, and stop.
-module(gs).
-behaviour(gen_server).
-export([main/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, handle_continue/2, terminate/2]).

main() ->
    process_flag(trap_exit, true),
    {ok, Pid} = gen_server:start_link({local, kv}, ?MODULE, [], []),
    io:format("started: ~w, registered: ~w~n", [is_pid(Pid), whereis(kv) =:= Pid]),
    ok = gen_server:cast(kv, {put, a, 1}),
    io:format("get a: ~w~n", [gen_server:call(kv, {get, a})]),
    io:format("put b: ~w~n", [gen_server:call(Pid, {put, b, 2})]),
    io:format("get c: ~w~n", [gen_server:call(kv, {get, c})]),
    kv ! hello,
    io:format("infos: ~w~n", [gen_server:call(kv, infos)]),
    {error, {already_started, P}} = gen_server:start({local, kv}, ?MODULE, [], []),
    io:format("already started: ~w~n", [P =:= Pid]),
    io:format("deferred: ~w~n", [gen_server:call(kv, deferred)]),
    io:format("slow: ~w~n", [reason(fun() -> gen_server:call(kv, slow, 50) end)]),
    io:format("continue: ~w, then ~w~n", [gen_server:call(kv, continue), gen_server:call(kv, continued)]),
    ok = gen_server:call(kv, {idle, 30}),
    receive after 100 -> ok end,
    io:format("timeouts: ~w~n", [gen_server:call(kv, timeouts)]),
    io:format("thrown: ~w~n", [gen_server:call(kv, throw)]),
    io:format("init stop: ~w~n", [gen_server:start(?MODULE, stop, [])]),
    io:format("init ignore: ~w~n", [gen_server:start(?MODULE, ignore, [])]),
    io:format("init crash: ~w~n", [short(gen_server:start(?MODULE, crash, []))]),
    {ok, Other} = gen_server:start(?MODULE, [], []),
    io:format("stopped: ~w, alive: ~w~n", [gen_server:stop(Other), is_process_alive(Other)]),
    io:format("crash: ~w~n", [reason(fun() -> gen_server:call(kv, crash) end)]),
    receive {'EXIT', Pid, Why} -> io:format("the starter saw it end: ~w~n", [short(Why)]) end,
    io:format("gone: ~w~n", [reason(fun() -> gen_server:call(kv, infos) end)]),
    io:format("stop gone: ~w~n", [catch gen_server:stop(kv)]),
    io:format("cast gone: ~w~n", [gen_server:cast(kv, x)]).

reason(F) ->
    try F() of
        V -> {value, V}
    catch
        exit:{R, {gen_server, call, _}} -> short(R)
    end.

short({error, R}) -> {error, short(R)};
short({R, Stack}) when is_list(Stack) -> R;
short(R) -> R.

init(stop) -> {stop, no};
init(ignore) -> ignore;
init(crash) -> erlang:error(boom);
init([]) -> {ok, #{data => #{}, infos => 0, timeouts => 0}}.

handle_call({get, K}, _From, S = #{data := D}) ->
    {reply, maps:get(K, D, none), S};
handle_call({put, K, V}, _From, S = #{data := D}) ->
    {reply, ok, S#{data := D#{K => V}}};
handle_call(infos, _From, S = #{infos := N}) ->
    {reply, N, S};
handle_call(deferred, From, S) ->
    {noreply, S#{pending => From}, 0};
handle_call(slow, _From, S) ->
    {noreply, S};
handle_call(continue, _From, S) ->
    {reply, ok, S, {continue, mark}};
handle_call(continued, _From, S) ->
    {reply, maps:get(marked, S, false), S};
handle_call({idle, Ms}, _From, S) ->
    {reply, ok, S, Ms};
handle_call(timeouts, _From, S = #{timeouts := N}) ->
    {reply, N, S};
handle_call(throw, _From, S) ->
    throw({reply, caught, S});
handle_call(crash, _From, _S) ->
    1 = length(id([])).

handle_cast({put, K, V}, S = #{data := D}) ->
    {noreply, S#{data := D#{K => V}}}.

handle_info(timeout, S = #{pending := From}) ->
    gen_server:reply(From, later),
    {noreply, maps:remove(pending, S)};
handle_info(timeout, S = #{timeouts := N}) ->
    {noreply, S#{timeouts := N + 1}};
handle_info(_, S = #{infos := N}) ->
    {noreply, S#{infos := N + 1}}.

handle_continue(mark, S) ->
    {noreply, S#{marked => true}}.

terminate(Reason, _S) ->
    io:format("terminate: ~w~n", [short(Reason)]).

id(X) -> X.
