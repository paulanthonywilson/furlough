---
layout: post
title: Memorable Password Generation with LiveView
date: 2020-06-18 11:37:39 +0100
author: Paul Wilson
categories: log elixir liveview
---

## tl;dr tips and tricks:

* [What happens to DOM changed with own Javascript rather than LiveView](#what-happens-to-dom-changed-outwith-liveview)
* [Debouncing when `phx-debounce` is not enough](#hand-rolled-debouncing)

Also you can try out the LiveView password generator [here](https://beta.correcthorsebatterystaple.com)

## This week

This week so far I've been coding in Elixir, and not doing a great job of logging. Thursday and Friday I am mostly attending the [virtual Elixir Conf EU](https://virtual.elixirconf.eu).

[Last week]({% post_url 2020-06-12-update-for-the-week-ending-12-june-2020 %}) we got to a point with deploying to AWS that worked but was a little bit messy. I'll talk about possible iterations on this at the end of the post.

Instead of spending another while on the deployment, though, I worked on something to deploy. It was based on my old app [Correct Horse Battery Staple](https://github.com/paulanthonywilson/correcthorsebatterystaple) based on the eponymous [XKCD comic](https://xkcd.com/936/) that generates secure but memorable passwords from random words. The original app is in Rails and uses a database to store the pool of words from which to [randomly generate passwords](https://github.com/paulanthonywilson/correcthorsebatterystaple/blob/c34ee9ceb6c0db4efe39e81bdbf916740c15707f/app/models/word.rb#L7).

## Correct Horse Battery Staple - Elixir Edition

This time the front end is in [Phoenix Live View](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html) and rather than a database, the pool of words is stored in an [ETS table](https://elixir-lang.org/getting-started/mix-otp/ets.html). I'm using an [Umbrella App](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html) because I am fond of making separate concerns really obvious. I find it helps clarify the separations. The app was created with 

```bash
mix phx.new correcthorse --live --umbrella --no-ecto
```

LiveView is an pleasure to develop in. The simplicity reminds me of how I felt in the early days of [Rails](https://rubyonrails.org): disbelief that I could achieve so much with so little code. The entire interactive front-end is handled from [this module](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/lib/correcthorse_web/live/password_live.ex) and the presentation from [this (mostly html) template](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/lib/correcthorse_web/live/password_live.html.leex).


### Live view event taster

For a quick taster we'll walk-through clicking the "Generate another" button.

The `phx-click` attribute in the template is all we need to bind the event.

```html
<button phx-click="generate-password">Generate another</button>
```

Then all we need to do is add an event handler to our module.

```elixir
def handle_event("generate-password", _, socket) do
  {:noreply, assign_new_password(socket)}
end
```

```elixir
defp assign_new_password(socket) do
  %{min_words: min_words, min_chars: min_chars} = socket.assigns

  assign_password(
    socket,
    Password.words(min_words, min_chars)
  )
end

defp assign_password(socket, wordlist) do
  assign(socket,
    wordlist: wordlist,
    password: generated_password(wordlist, socket)
  )
end
```

The minimum data is sent back to the page to update the template `<%= @password %>`.

```html
<input type="text" value="<%= @password %>"/>
```


### What happens to DOM changed outwith LiveView?

I added a little bit of local javascript to copy the password to the clipboard (with [`clipboard-copy`](https://www.npmjs.com/package/clipboard-copy)). The experience felt a bit flat and confusing, without some feedback to indicate success.

I unhid an element with the text "copied".

```javascript
copied.classList.remove("hidden")
```

Without any other code the change is undone on the receipt of any LiveView change event from the server, so it gets hidden as soon as there is some change. This fortunate side effect is exactly the behaviour I wanted, but it might be an annoyance in other circumstances.

### Hand-rolled debouncing

There are two range controls that determine the minimum number of words in the password, and the minimum number of characters in those words. Changing these should should regenerate the password, but only when we've finished sliding the controls. This is exactly what the [`phx-debounce`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-rate-limiting-events-with-debounce-and-throttle) tag is made for, but there's a problem: I also want to indicate the value of the control during the change, as below.

![Gif showing the control values changing as we slide but the password regenerates only when the sliding has finished](/assets/ch_debounce.gif)

Fortunately we are using Elixir where not only are the easy things easy, but the other stuff is usually also easy.

We can create a little [debouncing _Genserver_](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/lib/debounce/debouncer.ex). Then we can start it, with our processes' `_pid_` and a 500 millisecond debounce value; we assign its _pid_ to the socket on mounting.


```elixir
def mount(_params, _session, socket) do
  {:ok, debouncer} = Debouncer.start_link(self(), 500)

  socket =
    assign(socket,
      min_words: @default_min_words,
      min_chars: min_chars_from_min_words(@default_min_words),
      separator: "-",
      capitalise: :none,
      append: [],
      password: "",
      wordlist: [],
      _debouncer: debouncer
    )
```

Then when we get notification of a range update we let the _debouncer_ know, by calling `bounce/2` with the _pid_ and `generate_new_password`, as well as updating the range values.

```elixir
def handle_event("password-generation-details-changed", params, socket) do
  %{_debouncer: debouncer} = socket.assigns
  Debouncer.bounce(debouncer, :generate_new_password)
  {min_words, min_chars} = extract_min_words_chars(params)
  {:noreply, assign(socket, min_words: min_words, min_chars: min_chars)}
end
```

If no `bounce/2` has been called on the _debouncer_ for the 500 milliseconds, then the `:generate_new_password` message is sent back to the _LiveView_. We generate the new password while handling that message.

```elixir
def handle_info(:generate_new_password, socket) do
  {:noreply, assign_new_password(socket)}
end
```

What wizardry is this? Let's peek behind [the _debouncer_'s](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/lib/debounce/debouncer.ex) curtain.

It relies on some very useful [built-in](https://hexdocs.pm/elixir/GenServer.html#module-timeouts) _GenServer_ functionality. Returning an optional _timeout_ value in the tuple from one of the event handling callbacks (eg `handle_info/2`) causes a `:timeout` message to be sent to the _GenServer_ unless a message is received to the processes' queue before the timeout expires.

```elixir
defstruct receiver: nil, timeout: 0, last_message: nil

@type t :: %__MODULE__{
        receiver: pid,
        timeout: timeout(),
        last_message: any()
      }
```

The _GenServer_'s state holds

* the pid of the receiver, ie something to receive a message. Remember we pass in `self()` when it is started in our _LiveView_
* `timeout` - the 500 milliseconds we passed in
* `last_message` which is the message to send to the receiver.

```elixir
def bounce(pid, message) when message != :timeout do
  send(pid, message)
end
```

```elixir

def handle_info(message, s = %{timeout: timeout}) do
  {:noreply, %{s | last_message: message}, timeout}
end
```

When `bounce` is called then this sends a message to the _bouncer_. When the message is handled, the *last_message* is saved to the state and the `timeout` is returned as the third element in the tuple. The `:timeout` message is received unless another `bounce/2` occurs within the timeout period. 

While handling the timeout we send the *last_message* (`:generate_new_password`) back to our _LiveView_.

```elixir
def handle_info(:timeout, s = %{receiver: receiver, last_message: last_message}) do
  send(receiver, last_message)
  {:noreply, %{s | last_message: nil}}
end
```

### Testing

I have not been great about [testing driving the LiveView](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/test/correcthorse_web/live/password_live_test.exs). If I were to retrofit some tests, it would make sense to decouple the backend with a behaviour for stubs or mocks.

The _debouncer_ [is tested](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3229e0d67efc170a4001b0df4cd1d97808f68a4c/apps/correcthorse_web/test/correcthorse_web/debounce/debouncer_test.exs), as is the back-end.

### Backend - generating the passwords

I will write this up in a later post.

### Next functionality (possibly)

The app is pretty complete. I would quite to add an option for an alternative, more fun, pool of words extracted from a few books from [Project Gutenberg](https://www.gutenberg.org).

### Next projects

Possibly:

* A cheaper deploy without the load balancer, perhaps using [DNSimple](https://developer.dnsimple.com/v2/certificates/) to manage SSL certificates
* Deploying by user [Packer](https://www.packer.io) to build a custom AMI that include the release (and possibly ssl certificates).
* A package to generating the release scripts and Terraform etc .. for quick start project deployment.
* Something with [Nerves](https://www.nerves-project.org) which I haven't used for a while, and miss.







