%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% elixir_erl_pass is where Elixir's map.field goes when the map has no such
%% key or the term is no map: Elixir's own raises a KeyError, or calls the
%% function of a module the term is. Packed with an Elixir program by what it
%% reaches, and kept off the oracle's path.
-module(elixir_erl_pass).
-export([no_parens_remote/2]).

no_parens_remote(Map, Key) when is_map(Map) -> erlang:error({badkey, Key, Map});
no_parens_remote(Mod, Fun) when is_atom(Mod) -> Mod:Fun();
no_parens_remote(Other, _) -> erlang:error({badmap, Other}).
