# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Ping: two processes passing a message back and forth, as erl/pingpong.erl.
defmodule Ping do
  def start(n) do
    pong = spawn(fn -> pong() end)
    me = self()
    spawn(fn -> ping(me, pong, n, 0) end)

    receive do
      {:done, rounds} -> rounds
    end
  end

  defp ping(parent, pong, 0, rounds) do
    send(pong, :stop)
    send(parent, {:done, rounds})
  end

  defp ping(parent, pong, n, rounds) do
    send(pong, {:ping, self()})

    receive do
      :pong -> ping(parent, pong, n - 1, rounds + 1)
    end
  end

  defp pong do
    receive do
      {:ping, from} ->
        send(from, :pong)
        pong()

      :stop ->
        :ok
    end
  end

  def main, do: IO.puts("done #{start(10)}")
end
