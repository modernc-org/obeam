# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Fac: recursion with guards, a pipe through Enum.map, IO.inspect, and an
# interpolated string.
defmodule Fac do
  def fac(0), do: 1
  def fac(n) when n > 0, do: n * fac(n - 1)

  def main do
    [0, 1, 5, 10, 12] |> Enum.map(&fac/1) |> IO.inspect()
    IO.puts("fac(10) = #{fac(10)}")
  end
end
