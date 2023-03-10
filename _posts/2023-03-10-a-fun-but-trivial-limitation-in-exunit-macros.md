---
layout: post
title: A fun, but trivial, limitation in ExUnit (/Macros)
date: 2023-03-10 11:59:43 +0000
author: Paul Wilson
categories: elixir
---

Today I learnt that it is forbidden to use an attribute which is a [port](https://www.erlang.org/doc/reference_manual/data_types.html#port-identifier) or a ([reference](https://www.erlang.org/doc/reference_manual/data_types.html#reference)) in an [ExUnit](https://hexdocs.pm/elixir/Port.html) test. ([Pids](https://www.erlang.org/doc/reference_manual/data_types.html#pid) are just fine). 

```elixir
defmodule ScratchpadTest do
  use ExUnit.Case
  @port :erlang.list_to_port('#Port<0.1234>')

  test "porty worty" do
    @port
  end
end
```

Gets you

```
** (ArgumentError) cannot inject attribute @port into function/macro because cannot escape #Port<0.1234>. The supported values are: lists, tuples, maps, atoms, numbers, bitstrings, PIDs and remote functions in the format &Mod.fun/arity
```

It is, of course, super-easy to work around:

```elixir
defmodule ScratchpadTest do
  use ExUnit.Case

  test "porty worty" do
    assert is_port(:erlang.list_to_port('#Port<0.1234>'))
  end
end
```

You might, as I did, think the limitation was caused solely by `test/2` being a macro and I suppose it kind-of is. But it is easy to forget that Macros are everywhere in Elixir. This does not work. 

```elixir
defmodule ScratchpadTest do
  use ExUnit.Case
  @port :erlang.list_to_port('#Port<0.1234>')

  test "porty worty" do
    assert is_port(port())
  end

  defp port, do: @port
end

```
`defp/2` and `def/2` are also macros. This too does not compile

```elixir
defmodule Scratchpad do
  @port :erlang.list_to_port('#Port<0.1234>')
  def port, do: @port
end
```

Weirdly though this does compile, even though `defmodule/2` is a macro. 

```elixir
defmodule Scratchpad do
  @port :erlang.list_to_port('#Port<0.1234>')
  IO.inspect(@port)
end

```
No doubt if I was more learned, or put the research in, I would understand why. None of this is that important so 

¯\\(°_o)/¯☕️

Anyway, if you have read this far sorry (not sorry) for you learning nothing useful. I'm going back to some crazy test-driving of websocket client stuff using [Mint Websocket](https://hexdocs.pm/mint_web_socket/Mint.WebSocket.html).
