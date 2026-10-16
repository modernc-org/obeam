# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Ring: n processes in a ring and a token sent m times around it, as
# erl/ring.erl.
defmodule Ring do
  def start(n, m) do
    main = self()
    spawn(fn -> first(main, n, m) end)

    receive do
      {:done, hops} -> hops
    end
  end

  defp first(main, n, m) do
    next = build(n - 1, self())
    send(next, {:token, 1})
    rounds(main, next, m, 0)
  end

  defp build(0, first), do: first
  defp build(k, first), do: spawn(fn -> hop(build(k - 1, first)) end)

  defp hop(next) do
    receive do
      {:token, hops} ->
        send(next, {:token, hops + 1})
        hop(next)

      :stop ->
        send(next, :stop)
    end
  end

  defp rounds(main, next, m, done) do
    receive do
      {:token, hops} when done + 1 == m ->
        send(next, :stop)

        receive do
          :stop -> :ok
        end

        send(main, {:done, hops})

      {:token, hops} ->
        send(next, {:token, hops + 1})
        rounds(main, next, m, done + 1)
    end
  end

  def main, do: IO.puts("#{start(100, 100)} hops")
end
