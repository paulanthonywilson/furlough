---
layout: post
title: Binary WebSocket communication with Elixir & Phoenix
date: 2021-02-19 12:46:13 +0000
author: Paul Wilson
categories: elixir phoenix tutorial
---

One of the great things about [Phoenix](https://www.phoenixframework.org) has always been its Websocket support. This is implemented with developer-friendly abstractions over WebSockets, initially with [Channels](https://hexdocs.pm/phoenix/Phoenix.Channel.html#content), and now with the amazing [LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html). Very occasionally it is useful to have lower level access to the WebSockets in order to send binary messages.

I have been using the [Nerves Framework](https://hexdocs.pm/nerves/getting-started.html) and Phoenix servers to relay MJPEG streams from Raspberry Pi Zero cameras for a while[^1]. MJPEG streams are simply a rapid series of JPEG snapshots, sent and displayed one after another. JPEGs are binaries and the Phoenix channel abstractions use text transport. A bad (but common) option used to send binary messages over WebSockets is to Base 64 encode them, and send it using Phoenix Channels; when used for MJPEG streams, the image processing and message-size overhead causes noticeable lag on the stream. 

As well as text messages, the WebSockets protocol supports binary messages which are the best option for, well, binary messages. One way incorporate those into a Phoenix app is to fire up a separate Cowboy instance, on a different port to Phoenix, and use [Cowboy Websocket Handlers](https://ninenines.eu/docs/en/cowboy/2.8/guide/ws_handlers/) directly. I shared an example of this [here](https://elixirforum.com/t/how-to-build-a-photobooth-with-elixir-nerves/13802/13?).

There are plenty of other reasons for sending binary messages over WebSockets, other than for images, such as sending audio files or documents. Using [binary terms](https://erlang.org/doc/man/erlang.html#term_to_binary-1) to communicate between Erlang nodes on the Internet (eg Phoenix web-server to Nerves devices) is much simpler[^2] and more compact than JSON.


Previously, firing up a separate Cowboy seemed to me the simplest option, side-stepping what seemed to be some [hair-rising configuration](https://elixirforum.com/t/plan-old-websockets-in-phoenix-but-without-magic/10074) fiddliness to get custom WebSocket handlers working directly with Phoenix, which I could not be doing with. Though creating a separate Cowboy instance does mean using Nginx, or similar, as a proxy if you want to use only the standard ports (443 / 80) for your application.

Recently I was inspired to get rid of an Nginx frontend of a deployment and discovered that custom WebSocket handlers on the Phoenix Endpoint got a lot easier since 1.4, by implementing the [`Phoenix.Socket.Transport`](https://hexdocs.pm/phoenix/1.5.7/Phoenix.Socket.Transport.html) behaviour. I have put together a simple Phoenix app which can be used as a template for doing just this. It sends a stream of JPEG images down a websocket to display a jumping stick-figure in browser. You can browser through the code [here](https://github.com/paulanthonywilson/binary-websockets-example), but I will walk through the salient parts[^3].

![Gif of the example application being viewed in a browser](/assets/starjump.gif)


## Custom Socket 

Let's start with the [backend custom socket](https://github.com/paulanthonywilson/binary-websockets-example/blob/main/lib/starjumps_web/websockets/starjump_socket.ex). This implements `Phoenix.Socket.Transport`:

```elixir
defmodule StarjumpsWeb.Websockets.StarjumpSocket do
  @behaviour Phoenix.Socket.Transport

```

The `child_spec/1` callback is an opportunity to set up supporting processes during application initiation. We do not need any of that, so this is a no-op, (inspired by the Echo Server example [in the documentation](https://hexdocs.pm/phoenix/1.5.7/Phoenix.Socket.Transport.html#module-example)].

```elixir
  def child_spec(_opts) do
    %{id: Task, start: {Task, :start_link, [fn -> :ok end]}, restart: :transient}
  end
```

`connect/1` is called on receiving a connection from a client. Here we are expecting a couple of params: a token, to identify the client connection, and a jump-rate, roughly the number of milli-seconds between frame changes. We return an `:ok` tuple with the arguments that will be passed to the `init/1` callback.

```elixir
  def connect(%{params: %{"token" => token, "jump_rate" => jump_rate}}) do
    {:ok, %{token: token, jump_rate: String.to_integer(jump_rate)}}
  end
```

`init/1` receives the arguments from the `connect/1` and, being in the websocket connection's process, it can do a few things:

* Sends itself a message to initiate the first image to be sent

* Subscribes to receive updates to the jump rates associated with the client token. (`JumpRates` is a thin wrapper around `Phoenix.PubSub`)

* Just like `GenServer.init/1` the `:ok` return tuple initiates the state for the socket, where `next_image_in` is the number of milliseconds until the next image, and `jump` is the count of jumps so far.

```elixir
  def init(%{token: token, jump_rate: jump_rate}) do
    send(self(), :send_image)
    JumpRates.subscribe(token)
    {:ok, %{next_image_in: jump_rate, jump: 0}}
  end
```

As you would expect, messages are handled with `handle_info/2`. The `:send_image` handler schedules another `:send_image`.

```elixir
  def handle_info(:send_image, %{jump: jump, next_image_in: send_after} = state) do
    Process.send_after(self(), :send_image, send_after)
    {:push, {:binary, Starjumping.image(jump)}, %{state | jump: jump + 1}}
  end
```
There are three elements to this return tuple:-

* `:push` - the first element indicates that a message should be sent to the WebSocket client
* `{:binary, Starjumping.image(jump)}` - the second element specifies, with a tuple, the message to be sent. The `:binary` opcode makes this a binary message; the alternative is `:text`.
* `%{state | jump: jump + 1}` - the third element updates the socket state. We increment the jump count so that the correct image in the sequence will be sent next[^4]. 

The other `handle_info/2` handler deals with updating the rate of jumping (image sending). It is only a state change; we do not send any messages down the WebSocket, so we return an `:ok` tuple.

```elixir
  def handle_info({:jump_rate_change, new_next_image_in}, state) do
    {:ok, %{state | next_image_in: new_next_image_in}}
  end
```

`handle_in/2` handles messages sent from the client, which is presented as a tuple. The first element is the message itself and the second is an `opcode` which indicates the type of message - `:binary` or `:text`.

```elixir
  def handle_in({message, opts}, state) do
    Logger.debug(fn -> "handle_in with message: #{inspect(message)}, opts: #{inspect(opts)}" end)
    {:ok, state}
  end
```

`:terminate/2` is called when the socket is terminated.

```elixir
  def terminate(reason, _state) do
    Logger.debug(fn -> "terminating because #{inspect(reason)}" end)
    :ok
  end
```

### Mounting the socket on the endpoint

The custom socket needs to be mounted in the [application endpoint](https://github.com/paulanthonywilson/binary-websockets-example/blob/main/lib/starjumps_web/endpoint.ex). Here it is, next to the LiveView endpoint being mounted.

```elixir
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  socket "/star-jumping/:token/:jump_rate", StarjumpSocket
```

We have chosen to tokenise the url, so that the parameters "token" and "jump_rate" will form part of the url. When running the default dev environment on http, localhost, port 4000 then the full url for token "abc123" at jump rate 1,000 is 

```
ws://localhost:4000/star-jumping/abc123/1000/websocket".
```

Note that:-

* SSL connections need to have the "wss" protocol part, (count the s's).
* The "/websocket" suffix is a bit of gotcha. Some sockets can choose to support longpolling for legacy reasons, so the transport is explictly specified. See the [`socket/3` documentation](https://hexdocs.pm/phoenix/1.5.7/Phoenix.Endpoint.html#socket/3). (As longpolling can not support binary messages, this is not a consideration.)

### Setting up the client html

That's the backend done. To complete the demonstration we need to set up the client. In this case it is html + javascript. I am serving the page using LiveView, which at this point is my default for Phoenix applications. It is equally as straightforward to use a custom websocket with old-school controllers and templates, though some of the Javascript would need to vary a little.

The entire module is [here](https://github.com/paulanthonywilson/binary-websockets-example/blob/main/lib/starjumps_web/live/starjump_live.ex), but let's pick out a few parts, such as setting up the various values on mounting the page:

```elixir
  def mount(_params, _session, socket) do
    token = UUID.uuid4()
    jump_rate = default_jump_rate()
    image_ws_url = star_jump_image_ws_url(token, jump_rate, socket)
    {:ok, assign(socket, token: token, jump_rate: jump_rate, image_ws_url: image_ws_url)}
  end
```

Randomly generating a unique token here is a bit of a cheat for demonstration purposes. In a real application you might want to sign and/or encrypt a token that points to a particular resource. 

The `host_uri` attribute of the socket, along with the token and jump rate, is used to generate a full url; take a look at the implementation [here](https://github.com/paulanthonywilson/binary-websockets-example/blob/0290085a24e12828bfb3927b2bac7d31c8b12aef/lib/starjumps_web/websockets/starjump_helper.ex#L18).

The html is pretty simple, an `img` tag used to display the images sent down the WebSocket.

```elixir
  def render(assigns) do
    ~L"""
    <div class="row">
      <div class="column">
       <img data-binary-ws-url="<%= @image_ws_url %>"
            id="star-jump-img"
            phx-hook="ImageHook"
            src="/images/placeholder.jpg">
      </div>
      <div class="column">
          <form phx-change="change-jump-rate" class="change-jump-rate">
            <label for="jump-rate">Jump rate</label>
            <select name="jump-rate">
              <%=  options_for_select jump_rate_options(), @jump_rate %>
            </select>
          </form>
      </div>
    </div>
    """
  end
```

A [data attribute](https://developer.mozilla.org/en-US/docs/Learn/HTML/Howto/Use_data_attributes) is used to pass the the WebSocket connection url to the custom Javascript, and a [LiveView client hook](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks) is used to trigger that Javascript.


The other bit of html is setting up a drop-down, which changes the rate at which the image is changed. It's handler is pretty standard LiveView which broadcasts the rate over a topic to which (you will recall) the socket has subscribed. I have included it below to mention one thing.

```elixir
  def handle_event(
        "change-jump-rate",
        %{"jump-rate" => jump_rate},
        %{assigns: %{token: token}} = socket
      ) do
    jump_rate = String.to_integer(jump_rate)
    change_jump_rate(token, jump_rate)

    {:noreply,
     assign(socket,
       jump_rate: jump_rate,
       image_ws_url: star_jump_image_ws_url(token, jump_rate, socket)
     )}
  end
```

The url for connecting to the websocket is updated with the new jump rate. This is so that if the socket connection is lost, then the client Javascript will reconnect with the correct rate of jumping.

### The Javascript

Talking of Javascript, this is the `ImageHook` setup in our [`app.js`](https://github.com/paulanthonywilson/binary-websockets-example/blob/main/assets/js/app.js)

```javascript
import { ImageSocket } from "./image_socket.js"

let Hooks = {};

Hooks.ImageHook = {
    mounted() {
        let imageSocket = new ImageSocket(this.el);
        imageSocket.connect();
        this.imageSocket = imageSocket;
    },
    updated() {
        this.imageSocket.updated()
    }
}

```

Hooks are LiveView specific, and really handy for this kind of thing. This one is called when mounted and sets up the WebSocket wrapper, that we'll look at soon. It also calls the `updated` function on the wrapper when the image element is updated - in this case we would be interested that the websocket connection url has changed because the user updated the jump rate.

Of course the hook must be added to the LiveView.

```javascript
let liveSocket = new LiveSocket("/live", Socket, 
    { hooks: Hooks,
      params: { _csrf_token: csrfToken } })

```

The [`ImageSocket`](https://github.com/paulanthonywilson/binary-websockets-example/blob/main/assets/js/image_socket.js) Javascript class deals with connecting to the WebSocket, setting up the callbacks, and scheduling a heartbeat (see later).

```javascript

export class ImageSocket {
    constructor(img) {
        console.log("new image socket");
        this.img = img;
        this.imageUrl = this.img.src
        this.ws_url = img.dataset.binaryWsUrl;
        this.scheduleHeartBeat();
    }

    connect() {
        console.log("image socket connect");
        this.hasErrored = false;
        this.socket = new WebSocket(this.ws_url);
        let that = this;
        this.socket.onopen = () => { that.onOpen(); }
        this.socket.onclose = () => { that.onClose(); }
        this.socket.onerror = errorEvent => { that.onError(errorEvent); };
        this.socket.onmessage = messageEvent => { that.onMessage(messageEvent); };
        this.attemptReopen = true;
    }
```

The `onMessage` callback receives the binary messages, containing the images sent from the server.

```javascript

    onMessage(messageEvent) {
        if (typeof messageEvent.data != "string") {
            this.binaryMessage(messageEvent.data);
        }
    }

```

I've re-used this class from another project that can receive both text and binary messages; I've left the check in here to illustrate how to differentiate between the two. (The `typeof  messageEvent.data` for binary messages is "object", by the way.)


[URL.createObjectURL](https://developer.mozilla.org/en-US/docs/Web/API/URL/createObjectURL) is how we solve the problem of getting the binary image data displayed on the image. As the object url is tied to the window document, it is important to revoke the previous object urls to avoid a memory leak.

```javascript
    binaryMessage(content) {
        let oldImageUrl = this.img.src;
        this.imageUrl = URL.createObjectURL(content);
        this.img.src = this.imageUrl;

        if (oldImageUrl.startsWith("blob:")) {
            URL.revokeObjectURL(oldImageUrl);
        }
    }
```

That is pretty much it for displaying images via binary messages from a custom Phoenix WebSocket. For completeness, let's also take a quick look at what happens when the jump rate, hence the websocket connection url changes.

Remember the image hook calls `updated()` on our `ImageSocket` when the image element is changed by LiveView? Here's the `updated` function.

```javascript
    updated() {
        this.ws_url = this.img.dataset.binaryWsUrl;
        this.img.src = this.imageUrl;
    }
```

First we update our cached url (the alternative would be not to cache it). The second is a workaround for a LiveView thing - the `img.src` attribute is reset to the original placeholder value on an event update; this resets it to the last received image. (I've futzed around with moving the dataset and using `phx-update="ignore" attribute but have not got anywhere; no doubt I'm missing something.)

The last thing to consider is dealing with keeping the WebSocket alive, and dealing with the WebSocket closing despite our best efforts.

By default, and we are using the default, the WebSocket will [timeout after 60 seconds](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-websocket-configuration) of not receiving any messages from the client. We _could_ set this to infinity, but then we would certainly end up with zombie socket processes. To stop this happening a heartbeat is scheduled on 'ImageSocket' construction. The heartbeat regularly sends a small message to the server, preventing the socket being closed by timeout. 

```javascript
    scheduleHeartBeat() {
        let that = this;
        this.heartBeatId = setTimeout(function () { that.sendHeartBeat(); }, 30000);
    }

    sendHeartBeat() {
        if (this.socket) {
            // Send a heartbeat message to the server to let it know
            // we're still alive, avoiding timeout.
            this.socket.send("💙");
        }
        this.scheduleHeartBeat();
    }
```

If you clone and run [the example application](https://github.com/paulanthonywilson/binary-websockets-example) then you will see the heartbeat messages being logged in the console, on viewing the application in a browser.

![Heartbeat messages being logged to the console](/assets/websocket-heartbeats.png)


Despite our heartbeat we will still need to deal with the socket connection being lost due to network glitches etc ...

```javascript
    onError(errorEvent) {
        this.hasErrored = true;
        console.log("image socket error", errorEvent);
    }

    onClose() {
        this.maybeReopen();
        console.log("image socket ws closed", this);
    }

    isSocketClosed() {
        return this.socket == null || this.socket.readyState == 3;
    };

    maybeReopen() {
        let after = this.hasErrored ? 2000 : 0;
        setTimeout(() => {
            if (this.isSocketClosed() && this.attemptReopen) this.connect();
        }, after);
    };
```

In the case of a socket being closed due to an error then `on_error` is called, followed by `onClose`. In this case, closing with error delays the attempt to re-open for 2 seconds; otherwise a new connection is attempted immediately. This is somewhat arbitrary - your mileage may vary.

### Wrapup

Since 1.4.0, The `Phoenix.Transport.Socket` behaviour provides a simple way to be able to use binary WebSocket messages in your Phoenix application. While, most of the time the existing LiveView and Channel functionality will be perfect for you needs. However if you find yourself reaching for `Base.encode64/2` maybe you should think about using binary messages instead. That's what they are there for. 
















-- 


[^1]: I [talked](https://www.youtube.com/watch?v=ad4rlF_kxSI) about hardening one such project for production use at Elixir Conf EU in Prague.

[^2]: Not everything encodes to JSON without custom serialisation.

[^3]: I've taken a few liberties with the code copied to here, removing some logging, deleting comments, and making it a little less [DRY](https://en.wikipedia.org/wiki/Don't_repeat_yourself) in places.

[^4]: There's actually only two images, [selected through the magic of modulus](https://github.com/paulanthonywilson/binary-websockets-example/blob/6b934c597e29c45515eebf9bd8d8f17d54307c27/lib/starjumps/starjumping.ex#L11-L18).