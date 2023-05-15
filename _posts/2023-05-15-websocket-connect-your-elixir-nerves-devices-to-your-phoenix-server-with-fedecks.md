---
layout: post
title: Connect your Elixir Nerves devices to your Phoenix server over Websockets, with Fedecks
date: 2023-05-15 13:14:37 +0100
author: Paul Wilson
categories: elixir phoenix nerves
---

>  Fedecks makes it easy to establish duplex communication between your Elixir Nerves devices and your Phoenix Server in the cloud

Whatever your [Nerves](https://nerves-project.org) project does, there's a good chance that it can be enhanced by securely connecting to a [Phoenix Server](https://phoenixframework.org) in the cloud; it gives you the ability to can monitor and control your device from afar.

Websockets are a great medium for this connection. The provide two way communication without having to punch holes in your network router and they are secure (assuming your server is behind ssl). The can be a bit fiddly to set up though - except not any more. I've extracted a couple of hexicles from my projects to make things easier for you (and future me):

* _Fedecks Server_ is for the server side of things. Docs are [here](https://hexdocs.pm/fedecks_server/readme.html) and the source is [here](https://github.com/paulanthonywilson/fedecks_server).
* _Fedecks Client_ is for the Nerves side of things. Docs are [here](https://hexdocs.pm/fedecks_client) and the source is [here](https://github.com/paulanthonywilson/fedecks_client)

## Fedecks Features

* **Automatic re-establishes lost connection**. If your home network is anything like mine, this is pretty handy. Combine with [VintageHeart](https://hexdocs.pm/vintage_heart/readme.html) for extra network robustness.
* **After initial authentication, connection is automatically established between reboots**. Lose power or otherwise need to reboot your device? You don't need to keep logging on.
* **Handles pinging the server periodically to keep the connection awake**. If your client does not do this then the server will close the connection; you'd automatically reconnect but you lose some connectivity.
* **Closes and re-establishes  the connection if _pong_ not received for a _ping_**. Sometimes connections go down and the client receives no notifications, leaving a _zombie_ that looks connected. Fedecks client takes care of that.
* **No credentials are stored locally on the client** Subsequent authentication is via a token signed by the server. The token is periodically refreshed so it should always be usable. Persisting the token enables the reconnection between reboots. The expiry is pretty long, which suits me, but you can [configure it to be shorter](https://hexdocs.pm/fedecks_server/FedecksServer.FedecksHandler.html) on the server side.
* **No need to decode / encode yourself or mess with JSON**. Communicates with Elixir terms (but be aware that decoding is safe, so be careful or avoid using atoms).
* **Token or credentials are sent in a header**. I think it is simplest and safest to authenticate before upgrading the initial HTTP request to a websocket, but the initial request is a `GET`. Depending on your setup (eg proxied behind nginx), `GET` requests are prone to be logged to an access log which I think leaves credentials vulnerable to leaking if sent as request parameters. Headers seem like a safer option.


I ran through the basics of _Fedecks_ in my Lightning Talk at Elixir Conf EU 2023, but let's run through a simple implementation.

## Fedecks Server setup

In your Phoenix app, that you will eventually deploy to the cloud, the first and most obvious step is to add `fedecks_server` as a dependency.

```elixir
{:fedecks_server, "~> 0.1.2"}
```

###  FedecksServer.FedecksHandler implementation

Then you will need to implement a [Fedecks Handler](https://hexdocs.pm/fedecks_server/FedecksServer.FedecksHandler.html).

```elixir
defmodule MyServerWeb.MySocketHandler do
  @behaviour FedecksServer.FedecksHandler

  @impl FedecksHandler
  def otp_app, do: :my_server

```

The `authenticate?/1` callback also needs to be implemented. This will be called on initial authentication[^1] with credentials provided by the client in a map in whatever form you decide is appropriate. For example[^2]

```elixir
  def authenticate?(%{
        "username" => username,
        "password" => password,
        "fedecks-device-id" => _device_id
      }) do
    Plug.Crypto.secure_compare(username, "the_user") &&
      Plug.Crypto.secure_compare(password, "secure_password")
  end
```

Note that the framework will always add "fedecks-device-id" to the map. This could give you the opportunity to associate a device with a user. The device id is assumed to be a unique `String`. 

Let's also implement the _optional_ `connection_established/1` callback, which will then get called every time the client establishes a connection, regardless of whether `authenticate?/1` was called. As this callback takes place in the socket's process we can
subscribe to a topic that we can use to push messages to our Nerves device.  

```elixir
  def connection_established(device_id) do
     Phoenix.PubSub.subscribe(MyServer.PubSub, "nerves_downstream_topic.#{device_id}")
  end
```

We'll also implement the optional `handle_info/2` to receive messages to send downstream.

```elixir
  def handle_info(_device_id, {:send_downstream, message}) do
    {:push, message}
  end
```

Also let's implement `handle_in/2` to handle any messages sent from the Nerves box.

```elixir
  def handle_in(device_id, message) do
    Phoenix.PubSub.broadcast(
      MyServer.PubSub,
      "nerves_upstream_topic.#{device_id}",
      {:message_from_device, message}
    )
  end
end
```

### Configuration

Now we will need to add some stuff to our config. Let's assume `runtime.exs`

```elixir

config :my_server, MyServerWeb.MySocketHandler,
  salt: System.fetch_env!("FEDECKS_SALT"),
  secret: System.fetch_env!("FEDECKS_SECRET")

```

The salt and secret can both be generated with `mix phx.gen.secret` and are used to sign the token used for re-authentication. 

See [the handler documentation](https://hexdocs.pm/fedecks_server/FedecksServer.FedecksHandler.html) for other optional callbacks and configuration options.

### Add to the EndPoint

[`FedecksServer.Socket.fedecks_socket/2](https://hexdocs.pm/fedecks_server/FedecksServer.Socket.html#fedecks_socket/2) is a handy macro for adding Fedecks to your endpoint.

```elixir

defmodule MyServerWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_server

  import FedecksServer.Socket, only: [fedecks_socket: 1]

  ## etc...

  fedecks_socket(MyServerWeb.MySocketHandler)

  # etc ...
end
```

As we've omitted the path it defaults to mounting the socket at "/fedecks", or actually "fedecks/websocket" as Phoenix needs it to be differentiated from a long polling request, see [`Phoenix.Socket.Transport'](https://hexdocs.pm/phoenix/Phoenix.Socket.Transport.html). 

## Fedecks Client Setup

Now let's set up the Nerves client. Assuming you have installed Nerves, you can [create a new Nerves project](https://hexdocs.pm/nerves/getting-started.html#creating-a-new-nerves-app). (Alternatively just create a new Elixir mix project, with a supervision tree, for trying things out locally.)

Once that's done add fedecks client as dependency.

```elixir
  {:fedecks_client, "~> 0.1"}
```

### Create a Client module

Now let's create the client.

```elixir
defmodule MyNerves.SocketClient do
  use FedecksClient
```

Now we have to implement `device_id/0` to provide a unique id. For our purposes the hostname provided by Nerves should be enough[^3].

```elixir
  def device_id do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

```

We also need to provide the connection url. Chances are that you will want to load this from config, and vary it by `Mix.target/0` and/or `Mix.env/0`. For now we'll run things on our development machines and point to localhost[^4].

```elixir
  def connection_url do
    "ws://localhost:4000/fedecks/websocket"
  end
end
```

Note that for secure connections we will want the protocol to be "wss://"

See [the documentation](https://hexdocs.pm/fedecks_client/FedecksClient.html#callbacks) for other optional callbacks to implement.

### Add to the application supervision tree

In your `application.ex`

```elixir
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: MyNerves.Supervisor]
    children = [MyNerves.SocketClient] ++ children(target())

    Supervisor.start_link(children, opts)
  end
```

## Try Fedecks out


Now we can try things out. From your Nerves directory run `iex -S mix`. If  you run `:observer.start` then you should see the Fedecks Client processes in your supervision tree. Subscribe to get events and to check your "device id".

```elixir
iex(1)> :observer.start                  
:ok
iex(2)> MyNerves.SocketClient.subscribe()
:ok
iex(3)> MyNerves.SocketClient.device_id()
"Ossian"

```

"Ossian" is the name of my development laptop for reasons that I can not rightly remember. On a Nerves devices it will be something like "nerves-242a".

From your Phoenix Server directory  `iex -S mix phx.server`. Let's subscribe to receive messages from the client. 

```elixir
iex(2)> Phoenix.PubSub.subscribe(MyServer.PubSub, "nerves_upstream_topic.Ossian")
:ok

```

Obviously substitute "Ossian" above with your development machine's hostname.


Ok, let's try stuff out.

From your **client** iex console

```elixir
iex(4)> MyNerves.SocketClient.login(%{"username" => "the_user", "password" => "secure_password"})
:ok
iex(5)> flush
{MyNerves.SocketClient, :connecting}
{MyNerves.SocketClient, :connected}

```

Now let's send a message from the **client** to the **server**

**On the client**
```elixir
iex(6)> MyNerves.SocketClient.send({"hello", "matey"})
:ok
```

**On the server**
```elixir
iex(3)> flush
{:message_from_device, {"hello", "matey"}}
:ok
```

Now send a message from the **server** to the **client**.

**on the server**, substituting "Ossian" for you computer's hostname.
```elixir
iex(4)> Phoenix.PubSub.broadcast(MyServer.PubSub, "nerves_downstream_topic.Ossian", {:send_downstream, ["hi", "there"]})        
:ok
```

Now **on the client**
```elixir
iex(7)> flush
{MyNerves.SocketClient, {:message, ["hi", "there"]}}
:ok
```

There we go: two way arbitrary communication between the client and the server. There's one caveat: terms are decoded safely on either end, so unknown atoms will not decode.

## Future developments?

After the Lightning Talk at Elixir Conf in Lisbon, [Mat Trudel](https://mat.geeky.net) told me about the work he had done to Phoenix to make Websockets much more flexible with [WebSock](https://hexdocs.pm/websock). I would like to support that approach to upgrading to Websockets in plugs and/or controllers in Phoenix 1.7 +. 

I may also consider rolling presence tracking and message passing over Phoenix PubSub from my personal projects up into _Fedecks Server_.













---

---

[^1]: Assuming the device is not offline for a long period then you only need to authenticate this way one time: subsequent authentication is done with a signed token provided (and frequently refreshed) by the server.
[^2]: Let's take it as read that we're not really going to be hardcoding usernames and passwords.
[^3]: It's good enough for my projects, though [not absolutely guaranteed unique](https://github.com/nerves-project/boardid#caveats)
[^4]: Obviously this is just for trying things out. Remember though that if you do want to try from firmware on a device to your development machine (host), by default Nerves does not come with a ZeroConf MDN client so local computer names will not work; you will need to point it to your development box's IP address.


