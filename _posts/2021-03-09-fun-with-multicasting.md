---
layout: post
title: Making friends and influencing nodes, with multicasting
date: 2021-03-09 12:43:08 +0000
author: Paul Wilson
categories: elixir otp networking nerves
---

How are you going to make friends if no-one knows you exist? That can be a real problem for some Elixir nodes, for example a few [Raspberry Pi Zeroes](https://www.raspberrypi.org/pi-zero-w/) running [Nerves](https://www.nerves-project.org) on a local network. One answer is to use the power of multicasting. I will walk you through an easy implementation. You might want to grab a clone of the example repo for this post [here](https://github.com/paulanthonywilson/otp-multicast-example).

Multicasting is sending a message out to all that are listening, on the local network[^1], as opposed to sending messages to a specific destination. Specifically it means sending [UDP](https://en.wikipedia.org/wiki/User_Datagram_Protocol) messages to a 224.0.0.0/4 address[^2] on a particular port; to receive those messages then listen on the same port.

# Basic multicasting `GenServer`

Let's get started with a `GenServer` that will both listen for, and broadcast, multicast messages.

```elixir
defmodule Multicasting.BroadcasterReceiver do
  use GenServer

  @port (case Mix.env() do
           :test -> 49_002
           _ -> 49_001
         end)
  
  @active 1
  @multicast_group_ip {239, 2, 3, 4}
  @udp_options [
    :binary,
    active: @active,
    add_membership: {@multicast_group_ip, {0, 0, 0, 0}},
    multicast_loop: true
  ]

  
  def start_link(_) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, socket} = :gen_udp.open(@port, @udp_options)
    send(self(), :broadcast)
    {:ok, %{socket: socket}}
  end

```

Standard, named, GenServer to add to the supervision tree. On initialisation it opens up a UDP socket on `@port` with `@udp_options` using the Erlang module [`:gen_udp`'s `:open/2` function](https://erlang.org/doc/man/gen_udp.html#open-2). Like TCP ports we just need to choose one that's above 1023. We'll pick a different port for tests so we can `mix test` while also running in `dev` mode.

It's worth going through the `@udp_options` in detail.

* `:binary`: We will send and receive using Erlang binary as opposed to a list of bytes.
* `active: 1`: Received messages on the port will be sent as messages to this process, to a maximum of 1 message, at which point the socket will switch to `passive` mode. I will go into this in more detail later. (Spoiler: it gets switched back to `active` immediately.) 
* `add_membership: {% raw %}{{239, 2, 3, 4}, {0, 0, 0, 0}}{% endraw %}`: Join the multicast group on IP address "239.2.3.4" using our local IP addres "0.0.0.0". "0.0.0.0" means all available interfaces.
* `multicast_loop: true`: also receive the messages that are sent from this socket. This is quite useful, to confirm that everything is set up ok. Again, I will elaborate on this later.

The `init/1` function also sends a `:broadcast` message to its process. We could be modern and used [`handle_continue/2`](https://hexdocs.pm/elixir/GenServer.html#c:handle_continue/2) callback, but as we are setting up a repeating series of broadcasts a message is simpler.

```elixir
  @broadcast_interval 15_000    
  @message_prefix "multitastic"

  def handle_info(:broadcast, %{socket: socket} = state) do
    Process.send_after(self(), :broadcast, @broadcast_interval)
    :ok = :gen_udp.send(socket, @multicast_group_ip, @port, "#{@message_prefix}#{hostname()}")
    {:noreply, state}
  end
```

```elixir
  defp hostname do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end
```

A message containing the OS hostname, prefixed with "multitastic:", is broadcast to all interested parties in the multicast group, listening on the appropriate port.

As an interested party, with a socket in `active` mode, the message is picked up by

```elixir
  def handle_info({:udp, _port, ip, _port_number, @message_prefix <> hostname}, state) do
    Logger.info("Broadcast received from #{hostname} on #{format_ip(ip)}")
    {:noreply, state}
  end
```

```elixir
  defp format_ip(ip_tuple) do
    ip_tuple |> Tuple.to_list() |> Enum.join(".")
  end

```

Remember that we set `active: 1` in the UDP options, which means that as soon as we receive a multicast message the port switches to `passive` mode, so no more are received? This is to prevent a badly configured, or just naughty, sender from overflowing the receiver with messages: if the messages were coming in faster than we could process them, the the processes message queue would keep on growing and **bad things would happen** (tm). The [solution from Learn You Some Erlang](https://learnyousomeerlang.com/buckets-of-sockets) is to flip-flop between active and passive mode. Helpfully (on purpose) a message is sent to controlling process on being flipped to `passive`, and we can switch back to active using `:inet.setopts/2`.

```elixir
  def handle_info({:udp_passive, _}, %{socket: socket} = state) do
    :inet.setopts(socket, active: @active)
    {:noreply, state}
  end
```

As we can only revert to `active` on receipt of the message sent to the queue, it prevents the process queue growing much at all. Note that in this example we are using a super-conservative value of 1 for the number of messages received in active mode. It probably could (should) be a bit higher.

The full module, so far, is [here](https://github.com/paulanthonywilson/otp-multicast-example/blob/2902bd450086b0479794d0351fd0ff4a4637fab5/lib/multicasting/broadcaster_receiver.ex). All that remains is to add it to the application.

```elixir
defmodule Multicasting.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Multicasting.BroadcasterReceiver
    ]

    opts = [strategy: :one_for_one, name: Multicasting.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Now we can run `iex -S mix` and see our node's own presence.

```
18:36:33.885 [info]  Broadcast received from caesaraugustus on 192.168.0.11
iex(1)> 
18:36:48.885 [info]  Broadcast received from caesaraugustus on 192.168.0.11
 
18:37:03.886 [info]  Broadcast received from caesaraugustus on 192.168.0.11

```
It's still a pretty lonely life, though. If we try and run another node we get

```

18:38:24.599 [info]  Application multicasting exited: Multicasting.Application.start(:normal, []) returned an error: shutdown: failed to start child: Multicasting.BroadcasterReceiver
    ** (EXIT) an exception was raised:
        ** (MatchError) no match of right hand side value: {:error, :eaddrinuse}
            (multicasting 0.1.0) lib/multicasting/broadcaster_receiver.ex:36: Multicasting.BroadcasterReceiver.init/1
            (stdlib 3.13.2) gen_server.erl:417: :gen_server.init_it/2
            (stdlib 3.13.2) gen_server.erl:385: :gen_server.init_it/6

```

Only one OS process can bind to a port at a time. 😿😿😿😿😿😿😿😿😿

Cheer up though. If you did clone the example repository, I sneaked in a [Dockerfile](https://github.com/paulanthonywilson/otp-multicast-example/blob/2902bd450086b0479794d0351fd0ff4a4637fab5/Dockerfile), so you instead of `iex -S mix` you can run

```
 docker build -t multicast . && docker run -it multicast iex -S mix
```

Run that from a few  terminals and you can have a party 🥂🍾🎆.

```

18:46:34.764 [info]  Broadcast received from 172baf8436fc on 172.17.0.4
iex(1)> 
18:46:38.989 [info]  Broadcast received from 075bc1221641 on 172.17.0.2
 
18:46:47.469 [info]  Broadcast received from 564d411984a5 on 172.17.0.3
 
18:46:49.762 [info]  Broadcast received from 172baf8436fc on 172.17.0.4
 
18:46:54.024 [info]  Broadcast received from 075bc1221641 on 172.17.0.2
 ```

## Adding a touch of resiliance

Using similar code on a few Nerves installations, I found that occasionally a node would remain isolated - neither receiving or sending multicast messages on the local network. Killing the process, and having the supervision tree restart it, solved the problem.  My hypothesis is that it is a timing issue - the socket being created before the WiFi connection was established.

A possible solution would be to subscribe to [VintageNet](https://github.com/nerves-networking/vintage_net) for networking updates and take appropriate action, such as re-opening the socket. I dislike this approach for a few reasons. One is that it couples slightly higher level code to a specificly Nerves-flavoured network implementation; it would make running the application on my development machine more awkward. Another is that my experience of debugging and confirming fixes for intermittent network issues is horribly painful. It is so hard to be sure the problem has been fixed, rather than it randomly not happening.

Let's add a new `GenServer` that will die if not touched every so often.

```elixir
defmodule Multicasting.Tick do
  use GenServer

  def start_link(opts) do
    {timeout, opts} = Keyword.pop!(opts, :timeout)
    GenServer.start_link(__MODULE__, timeout, opts)
  end

  def init(timeout) do
    {:ok, %{timeout: timeout}, timeout}
  end

  def tick(server) do
    GenServer.cast(server, :tick)
  end

  def handle_cast(:tick, %{timeout: timeout} = s) do
    {:noreply, s, timeout}
  end

  def handle_info(:timeout, s) do
    {:stop, :normal, s}
  end
end
```

Calling tick before the configured timeout time, keeps the process alive. Now lets integrate both with a supervisor.

```elixir
defmodule Multicasting.BroadcasterReceiverSupervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(arg) do
    children = [
      {Multicasting.Tick, [timeout: 35_000, name: :broadcaster_receiver_tick]},
      Multicasting.BroadcasterReceiver
    ]
    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

The `Tick` is configured with a 35 second timeout. The supervision strategy is `:one_for_all`, so that when one process dies (ie the `Tick`) they are all restarted. (`:rest_for_one` would also work here).

We swap in that supervisor for the `BroadcasterReceiver` in the application supervisor.

```elixir
  def start(_type, _args) do
    children = [
      Multicasting.BroadcasterReceiverSupervisor
    ]

    opts = [strategy: :one_for_one, name: Multicasting.Supervisor]
    Supervisor.start_link(children, opts)
  end
```

In the `BroadcasterReceiver` we call Tick on receipt of a message. Even if there are no other friends on the network then we will still receive a message every 15 seconds as we are listening to ourselves because of the `multicast_loop: true` option.

```elixir
  def handle_info({:udp, _port, ip, _port_number, @message_prefix <> hostname}, state) do
    Multicasting.Tick.tick(:broadcaster_receiver_tick)
    Logger.info("Broadcast received from #{hostname} on #{format_ip(ip)}")
    {:noreply, state}
  end
```

Using this strategy to ensure the multicast is working means we can not set `multicast_loop: true` unless we are comfortable restarting the process every 35 seconds (though that might not be too bad). It may be better to filter out our own messages here, in the application code.
## Caution

I probably don't need to say this, this is not secure communication. Broadcasting on a network means that any node, friendly or not, can listen in and/or spoof the messages. Be cautious.
## References

* I already linked to the relevant page on [Learn you some Erlang](https://learnyousomeerlang.com/buckets-of-sockets)
* I first got a multicast implementation working via [this blog post](https://dbeck.github.io/Scalesmall-W5-UDP-Multicast-Mixed-With-TCP/); I think I was on a train south to an [Elixir London](http://www.elixir.london).

--- 

[^1]: Effectively the local network. In theory you can broadcast your message over more than the local network by increasing the [`multicast_ttl`](https://tldp.org/HOWTO/Multicast-HOWTO-6.html) value to greater than 1, but I have no idea how this would really work on a [NAT](https://en.wikipedia.org/wiki/Network_address_translation)'d network.

[^2]: IPv4 address. While I know IPv6 multicasting exists that is _all_ I know about it. 
