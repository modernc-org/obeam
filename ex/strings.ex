# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Strings: interpolation of every kind to_string takes, <> and the bit
# syntax's construction, iodata to IO.puts, and inspect's forms of the terms
# M6a has: atoms, aliases, strings with escapes, charlists, keyword lists,
# improper lists, tuples and binaries that are no text.
defmodule Strings do
  def main do
    name = "world"
    n = 42
    IO.puts("hello, #{name}! #{n} #{:atom} #{3.5} #{~c"abc"} #{nil}|")
    IO.inspect({:ok, 1, "two", [3, 4], ~c"five", nil, true, Strings, :"with space"})
    IO.inspect(a: 1, b: "x", "c d": :e)
    IO.inspect([1 | 2])
    IO.inspect(<<1, 2, 3>>)
    IO.inspect("quote \" backslash \\ newline \n tab \t hash \#{x}")
    IO.inspect({[], {}, :+, -7, 2.5})
    IO.puts(inspect([1, 2, 3]) <> " " <> inspect(:ok) <> " " <> to_string(byte_size("hello")))
    b = <<65, 66::16, "cd", 0x41::utf8, 0x2603::utf8>>
    IO.inspect({b, byte_size(b)})
    IO.puts([~c"char", "data", ?!, [32, "nested", [?.]]])
    IO.puts(:an_atom)
    IO.puts(12_345)
  end
end
