# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Maps: map literals and updates, pattern matching on maps and binaries,
# structs and their access and update, ranges, Map functions, Enum over a
# map and a range, and inspect of each. A map with atom keys is printed
# sorted: elixir prints its keys in the order of its atom table, which no
# other VM has.
defmodule Point do
  defstruct x: 0, y: 0, label: nil
end

defmodule Maps do
  def norm1(%Point{x: x, y: y}), do: abs(x) + abs(y)

  def kind(%{type: :circle, r: r}), do: {:circle, r * r * 3}
  def kind(%{type: :square, side: s}), do: {:square, s * s}
  def kind(%{}), do: :unknown

  def header(<<"GET ", path::binary>>), do: {:get, path}
  def header(<<len::16, body::binary-size(len), _::binary>>), do: {:sized, body}
  def header(other), do: {:other, other}

  def sorted(map), do: map |> Map.to_list() |> Enum.sort()

  def main do
    m = %{"one" => 1, "two" => 2}
    m = Map.put(m, "three", 3)
    IO.inspect(m)
    IO.inspect(%{1 => :a, {2, 3} => [4], "s" => "t"})
    IO.inspect(%{a: 1})
    IO.inspect(%{})
    IO.inspect({Map.get(m, "two"), Map.get(m, "nine", :none), Map.fetch(m, "one"), Map.has_key?(m, "x")})
    IO.inspect(sorted(%{b: 2, a: 1, c: 3}))
    IO.inspect(Map.keys(%{3 => :c, 1 => :a, 2 => :b}))
    IO.inspect(Map.values(Map.merge(%{1 => :a}, %{2 => :b})))
    IO.inspect(Map.delete(%{1 => :a, 2 => :b}, 1))
    p = %Point{x: 3, y: -4}
    IO.inspect(p)
    IO.inspect(%{p | label: "corner"})
    IO.inspect({p.x, p.y, norm1(p)})
    IO.inspect(Enum.map([%{type: :circle, r: 2}, %{type: :square, side: 3}, %{type: :none}], &kind/1))
    IO.inspect(1..5)
    IO.inspect(1..10//3)
    IO.inspect(Enum.map(1..5, &(&1 * &1)))
    IO.inspect(Enum.sum(1..100))
    IO.inspect(Enum.map(%{1 => 10, 2 => 20}, fn {k, v} -> k + v end))
    IO.inspect(for x <- 1..4, do: x * 2)
    IO.inspect(Enum.map(["GET /a", <<0, 2, "hi", "rest">>, "other"], &header/1))
    counts = Enum.reduce(~w(a b a c b a), %{}, fn w, acc -> Map.update(acc, w, 1, &(&1 + 1)) end)
    IO.inspect(counts)
  end
end
