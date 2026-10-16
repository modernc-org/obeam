# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Enums: the Enum functions the shim has, on lists, with anonymous functions
# and captures, and a pipeline.
defmodule Enums do
  def seq(a, b) when a > b, do: []
  def seq(a, b), do: [a | seq(a + 1, b)]

  def main do
    l = seq(1, 10)
    IO.inspect(Enum.map(l, fn x -> x * x end))
    IO.inspect(Enum.filter(l, fn x -> rem(x, 2) == 0 end))
    IO.inspect(Enum.reduce(l, 0, fn x, acc -> x + acc end))
    IO.inspect({Enum.sum(l), Enum.count(l), Enum.member?(l, 5), Enum.member?(l, 11)})
    IO.inspect(Enum.reverse(l))
    Enum.each([1, 2, 3], fn x -> IO.puts("item #{x}") end)
    l |> Enum.map(&(&1 + 1)) |> Enum.filter(&(&1 > 5)) |> IO.inspect()
  end
end
