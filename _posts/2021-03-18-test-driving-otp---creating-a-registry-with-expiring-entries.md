---
layout: post
title: Test Driving OTP -  creating a registry with expiring entries
date: 2021-03-18 10:14:51 +0000
author: Paul Wilson
categories: elixir otp tdd
---

Previously [I wrote]({% post_url 2021-03-09-fun-with-multicasting %}) about using multicasting to advertise a node's existence, and receive notifications of the existence of other nodes. What if we wanted to keep a record of these other friendly nodes? I think that:

* It will be a transient record, so there is no need for a persistent store - keeping it in memory will be fine.
* We want to forget about nodes that we haven't heard from in a while - they are probably down or inactive
* We will want to [test drive](https://wiki.c2.com/?TestDrivenDevelopment) the implementation, as we are professional programmers that want to write code that is easy to refactor and we have confidence works as we intended.

## Basic functionality

First let's start with a test before even defining the module under test. Partly it's a ritual, but it does help us get into the frame of mind of writing the test before the production code.

```elixir
defmodule Multicasting.ExpiringRegistryTest do
  use ExUnit.Case
  alias Multicasting.ExpiringRegistry

  setup do
    {:ok, expiring_registry} = ExpiringRegistry.start_link([])
    {:ok, expiring_registry: expiring_registry}
  end

  test "registering and retrieving a key and value", %{
    expiring_registry: expiring_registry
   } do
    assert :ok == ExpiringRegistry.register(expiring_registry, "k1", "v1")
    assert [{"k1", "v1"}] == ExpiringRegistry.registrations(expiring_registry)
  end
end
```

We run the test and see that the module has not been defined. Now we can define the module and functions, so the tests run but still fail.

```elixir
defmodule Multicasting.ExpiringRegistry do
  def start_link(_args) do
  end

  def register(server, key, value) do
  end

  def registrations(server) do
  end
end
```

Next let's add a simple implementation: a GenServer holding state as a map.

```elixir
defmodule Multicasting.ExpiringRegistry do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, {}, opts)
  end

  def init(_opts) do
    {:ok, %{}}
  end

  def register(server, key, value) do
    GenServer.cast(server, {:register, {key, value}})
    :ok
  end

  def registrations(server) do
    GenServer.call(server, :registrations)
  end

  def handle_call(:registrations, _from, state) do
    registrations = Enum.map(state, fn {k, v} -> {k, v} end)
    {:reply, registrations, state}
  end

  def handle_cast({:register, {key, value}}, state) do
    {:noreply, Map.put(state, key, value)}
  end
end
```

We will add a few more tests to better define and stablise the behaviour.


```elixir
# in  Multicasting.ExpiringRegistryTest

  test "value for same key is updated", %{
    expiring_registry: expiring_registry
  } do
    :ok = ExpiringRegistry.register(expiring_registry, "k1", "v1")
    :ok = ExpiringRegistry.register(expiring_registry, "k1", "v2")
    assert [{"k1", "v2"}] == ExpiringRegistry.registrations(expiring_registry)
  end

  test "values for different keys are added to the registrations", %{
    expiring_registry: expiring_registry
  } do
    :ok = ExpiringRegistry.register(expiring_registry, "k1", "v1")
    :ok = ExpiringRegistry.register(expiring_registry, "k2", "v2")

    assert [{"k1", "v1"}, {"k2", "v2"}] ==
             ExpiringRegistry.registrations(expiring_registry)
  end

```

## Expiry???

Now let's make the entries expire ... 

```elixir
  test "values in the expiring_registry expire", %{
    expiring_registry: expiring_registry
  } do
    # 🤔 what goes here, then?
  end
```

Indeed, what goes in the the test body. We could configure the expiry time to be something very short, wait for longer than that time, and assert the absense of the entry. We would also want to ensure its presence before the expiry time.

I am not too keen on that approach as getting those timings right can be awkward and can changue upredictably, for instance when running in cloud-based CI containers. Those annoying flakey tests (intermittent test failures) that plague[^1] continuous server pipelines of larger applications are often down to timing issues.

Instead we will cheat, peek inside the (grey box), and use that information to cause the expiry. It is time to plan ahead and decide how we will implement this. We have several options, but let's go with associating each entry with a process that will stop itself if it is not prodded to be kept alive. Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html) provides some functionality we can use: entries are automatically removed on the death of their registering process.

## Refactor use use the Elixir Registry

First let's refactor[^2] to store the entries in a `Registry`, rather than a `Map`. In the tests

```elixir
  # in  Multicasting.ExpiringRegistryTest

  @registry_name String.to_atom("#{__MODULE__}Registry")

  setup do
    {:ok, _} = Registry.start_link(keys: :unique, name: @registry_name)
    {:ok, expiring_registry} = ExpiringRegistry.start_link(
      registry_name: @registry_name)
    {:ok, expiring_registry: expiring_registry}
  end
```

We are creating a unique name for the registry per test, ortherwise we get intermittent name clashes when one test starts before a previous test's registry has completed shutdown. There are alternatives, like starting a registry in `test_helper.exs` but I would prefer to keep everything together. 

The changes to the production code are a bit more radical.

```elixir
defmodule Multicasting.ExpiringRegistry do
  use GenServer

  @spec start_link(keyword()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    {registry_name, opts} = Keyword.pop!(opts, :registry_name)
    GenServer.start_link(__MODULE__, registry_name, opts)
  end

  def init(registry_name) do
    {:ok, %{registry_name: registry_name}}
  end

```

... 

{% raw %}
```elixir 

  def handle_call(:registrations, _from, %{registry_name: registry_name} = state) do
    registrations =
      registry_name
      |> Registry.select([{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])

    {:reply, registrations, state}
  end

  def handle_cast({:register, {key, value}}, %{registry_name: registry_name} = state) do
    case Registry.register(registry_name, key, value) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, _}} ->
        Registry.update_value(registry_name, key, fn _ -> value end)
    end

    {:noreply, state}
  end
end
```

{% endraw %}

(See [documentation](https://hexdocs.pm/elixir/Registry.html#select/2) for `Registry.select/2`)

## Actually implement expiry

We have now changed the underlying implementation and are tests still pass. Now for the expiry.

```elixir

  test "values in the expiring_registry expire",
       %{expiring_registry: expiring_registry, registry_name: registry_name} do
    ExpiringRegistry.register(expiring_registry, "k1", "v1")
    :sys.get_state(expiring_registry)
    [{entry_pid, _}] = Registry.lookup(registry_name, "k1")

    send(entry_pid, :timeout)

    assert [] = ExpiringRegistry.registrations(expiring_registry)
  end
```

While the `:sys.get_state/1` call looks a bit odd; it's a handy trick for ensuring the the `GenServer.cast/2` on the target has been completed before executing the next test instructions; as `:sys/get_state/1` is like `GenServer.call/2` in that it blocks until the message to the process has completed processing, it ensures the messages ahead of it in the queue have completed before returning. 

`Registry.lookup/2` returns a list of tuples of items stored against the key[^3]. The first element in the tuple is the registering process, and the second is the value.

We send a `:timeout` message to the registering process, indicating that its time is nigh. Of course the test fails because we have not implemented expiry.

```
  1) test values in the expiring_registry expire (Multicasting.ExpiringRegistryTest)
     test/multicasting/expiring_registry_test.exs:37
     match (=) failed
     code:  assert [] = ExpiringRegistry.registrations(expiring_registry)
     left:  []
     right: [{"k1", "v1"}]
     stacktrace:
       test/multicasting/expiring_registry_test.exs:45: (test)
```

Ok, deep breath and lets get it all working. We want the process that registers the entry to be specific to the entry, and for it to timeout. What I want to do is to, in order:

1. Get the broad shape of the architecture in place
1. Make sure that all of it works
1. See if there is any refactoring that would make it cleaner.

For the first step I am going to skip the test for updating existing entries; it reduces the things in play at one time, and we can worry about that at step 2.

```elixir
  @tag skip: true
  test "value for same key is updated", %{ expiring_registry: expiring_registry } do
```

I will want a GenServer responsible for the lifecycle of a registry entry. It's a bit involved so I will break up the implementation with commentary:

```elixir
defmodule Multicasting.ExpiringRegistryEntry do
  use GenServer, restart: :transient
```

> Restart is transient because once an entry expires we do not want our supervision tree to resurrect its likeness; when it's gone, we want it gone.

```elixir
  @expiry_time 35_000
```

> 35 second expiry seems fine for keeping track of something that we would expect to see every 15 seconds. You could argue that this part of the code should be more generic, and the expiry time ought to be passed in on process initialisation; you could be right.

```elixir

  def start_link({_registry_name, _key, _value} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init({registry_name, key, value}) do
    {:ok, _pid} = Registry.register(registry_name, key, value)
    {:ok, %{registry_name: registry_name, key: key}, @expiry_time}
  end

```

> Registering the key and value within the `init/1` function, means that the value will be registered before the `start_link/1` returns; I will come back to why I think this is important later.

> The `init/1` function returns the `@expiry_time` as part of its return tuple, so that if no more messages are sent to the process before the 35 seconds is up then a `:timeout` message will be sent.

```elixir

  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end
end
```
> The timeout handler stops the process, which will result in the entry being removed from the `Registry`.

To start this we are going to want to add a dynamic supervisor to our supervsion tree

```elixir
  # in Multicasting.Application 
  def start(_type, _args) do
    children = [
      Multicasting.BroadcasterReceiverSupervisor,
      {DynamicSupervisor, strategy: :one_for_one, name: Multicasting.DynamicSupervisor}
    ]
 
    opts = [strategy: :one_for_one, name: Multicasting.Supervisor]
    Supervisor.start_link(children, opts)
  end
```
Now instead of directly registering a key/value in our expiring registry, we will kick off the process which will take care of the registration.

```elixir
 # in Multicasting.ExpiringRegistry
   def handle_cast({:register, {key, value}}, %{registry_name: registry_name} = state) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Multicasting.DynamicSupervisor,
        {ExpiringRegistryEntry, {registry_name, key, value}}
      )

    {:noreply, state}
  end

```

Now lets try the expiry test.

```
*.

  1) test values in the expiring_registry expire (Multicasting.ExpiringRegistryTest)
     test/multicasting/expiring_registry_test.exs:36
     match (=) failed
     code:  assert [] = ExpiringRegistry.registrations(expiring_registry)
     left:  []
     right: [{"k1", "v1"}]
     stacktrace:
       test/multicasting/expiring_registry_test.exs:45: (test)

.

Finished in 0.07 seconds
4 tests, 1 failure, 1 skipped

```

Disaster! It still fails.

The timeout message hasn't had time to be handled, and let the process die. We could cede the scheduler with `:timer.sleep(1)` between sending the `:timout` message and  checking the registry contents, _which works on my machine_ but has strong flaky test vibes. Instead, let's be a bit safer.

```elixir
  test "values in the expiring_registry expire",
       %{expiring_registry: expiring_registry, registry_name: registry_name} do
    ExpiringRegistry.register(expiring_registry, "k1", "v1")
    :sys.get_state(expiring_registry)
    [{entry_pid, _}] = Registry.lookup(registry_name, "k1")

    send(entry_pid, :timeout)

    assert [] ==
             wait_until_equals(
               [],
               fn -> ExpiringRegistry.registrations(expiring_registry) end
             )
  end

  defp wait_until_equals(expected, actual_fn, attempt_count \\ 0)
  defp wait_until_equals(_expected, actual_fn, 100), do: actual_fn.()

  defp wait_until_equals(expected, actual_fn, attempt_count) do
    case actual_fn.() do
      ^expected -> expected

      _ ->
        :timer.sleep(1)
        wait_until_equals(expected, actual_fn, attempt_count + 1)
    end
  end
```


```
mix test test/multicasting/expiring_registry_test.exs

*...

Finished in 0.07 seconds
4 tests, 0 failures, 1 skipped
```

Aside: tests that are passing because of a mistake in the test code happen fairly frequently. For my confidence, I would want to see that modified test failing so would comment out the registering production code; watch it fail; then revert the change.


Now let's remove the skip tag and ... it go boom, of course.

```
  1) test value for same key is updated (Multicasting.ExpiringRegistryTest)
     test/multicasting/expiring_registry_test.exs:19
     ** (EXIT from #PID<0.172.0>) an exception was raised:
         ** (MatchError) no match of right hand side value: {:error, {{:badmatch, {:error, {:already_registered, #PID<0.176.0>}}}
         ...
```

But we can fix that.

```elixir
  # in Multicasting.ExpiringRegistry
  def handle_cast({:register, {key, value}}, %{registry_name: registry_name} = state) do
    case Registry.lookup(registry_name, key) do
      [{entry_pid, _}] ->
        :ok = ExpiringRegistryEntry.update(entry_pid, value)

      [] ->
        {:ok, _pid} =
          DynamicSupervisor.start_child(
            Multicasting.DynamicSupervisor,
            {ExpiringRegistryEntry, {registry_name, key, value}}
          )
    end
    {:noreply, state}
  end
```

```elixir 
  # in Multicasting.ExpiringRegistryEntry

  def update(pid, value) do
    GenServer.call(pid, {:update, value})
  end

  def handle_call({:update, value}, _, %{registry_name: registry_name, key: key} = state) do
    {^value, _} = Registry.update_value(registry_name, key, fn _ -> value end)
    {:reply, :ok, state, @expiry_time}
  end
```

Now we can

```
$ mtest test/multicasting/expiring_registry_test.exs
....

Finished in 0.07 seconds
4 tests, 0 failures
```

You may have noticed that we are testing handling of the `:timeout` message but not that any such message will ever happen. I am fairly comfortable with that; including the timeout in the `init/1` and `handle_call/2` is trivial and I would not be inclined to test it. On the other hand if you did insist, I would not feel strongly enough to argue.

```elixir
  test "timeout is set when creating or updating entries", %{registry_name: registry_name} do
    assert {:ok, _, 35_000} = ExpiringRegistryEntry.init({registry_name, "k1", "v1"})

    assert {:reply, _, _, 35_000} =
             ExpiringRegistryEntry.handle_call({:update, "v1"}, {}, %{
               registry_name: registry_name,
               key: "k1"
             })
  end
```

We are about done, but let's have a think about any edge/race conditions.

If two entries for the same key came in at the same time, could we end up trying to create a new entry twice? No, because the `ExpiringRegistry` `GenServer` acts as a bottleneck, meaning only one at a time can be processed. As the key/values for new keys are registered in `ExpiringRegistryEntry.init/1`, blocking the `ExpiringRegistryEntry.start_link/1` until that is completed, the registrations will have occurred before any subsequent `ExpiringRegistry` message is processed.

How about if an entry times out just as an update for that key comes in? That could be a problem, and lets see if we can reproduce it with a test.

```elixir
  alias Multicasting.ExpiringRegistryEntry

  test "timeout and update race condition", %{
    expiring_registry: expiring_registry,
    registry_name: registry_name
  } do
    ExpiringRegistry.register(expiring_registry, "k1", "v1")
    :sys.get_state(expiring_registry)
    [{entry_pid, _}] = Registry.lookup(registry_name, "k1")

    send(entry_pid, :timeout)
    ExpiringRegistry.register(expiring_registry, "k1", "v2")
    assert [{"k1", "v2"}] == ExpiringRegistry.registrations(expiring_registry)
  end
```

Oh, we can and it is not pretty.

```
18:28:39.345 [error] GenServer #PID<0.179.0> terminating
** (stop) exited in: GenServer.call(#PID<0.180.0>, {:update, "v2"}, 5000)
    ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly becau
```

Let's fix it

```elixir

  def handle_cast({:register, {key, value}}, %{registry_name: registry_name} = state) do
    case Registry.lookup(registry_name, key) do
      [{entry_pid, _}] ->
        update_entry(entry_pid, registry_name, key, value)

      [] ->
        new_entry(registry_name, key, value)
    end

    {:noreply, state}
  end

  defp update_entry(entry_pid, registry_name, key, value) do
    :ok = ExpiringRegistryEntry.update(entry_pid, value)
  catch
    :exit, _value ->
      new_entry(registry_name, key, value)
  end

  defp new_entry(registry_name, key, value) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Multicasting.DynamicSupervisor,
        {ExpiringRegistryEntry, {registry_name, key, value}}
      )
  end
```

And we are functionally done with the registry.

Our next step is to see if there is further refactoring to reduce duplication or make things clearer or more tidy. I am pretty satisfied with things as they are[^4]; things are _good enough_ though not perfect. We could maybe consider things like not bottlenecking the registry functionality through a single GenServer, while considering how that might introduce more recase conditions, creating a dedicated _module based_ dynamic supervisor for the registry entries, or adding a supervisor for all the registry things.

## Wait, did you just rewrite the implementation three kinds like it was a good thing?

Yeah, I kind-of did. I would not necessarily code like this all the time, but being able and comfortable doing so is a useful skill. It splits the task into:

1. Deciding how we want our code to behave

1. Working out how we want to implement the behaviour

1. Checking, early, that our implementation plan works as we expect. Maybe you have the full behaviour of `Registry` at the front of your mind, but I am quite old and don't use it that often; I need to read the documentation, and check my understanding.

1. Completing the task.

## Ok, let's see it in action

```elixir
 # in Multicasting.Application

   def start(_type, _args) do
    children = [
      Multicasting.BroadcasterReceiverSupervisor,
      {DynamicSupervisor, strategy: :one_for_one, name: Multicasting.DynamicSupervisor},
      {Registry, keys: :unique, name: :multicast_host_internal_registry},
      {Multicasting.ExpiringRegistry,
       name: :multicast_host_registry, registry_name: :multicast_host_internal_registry}
    ]

    opts = [strategy: :one_for_one, name: Multicasting.Supervisor]
    Supervisor.start_link(children, opts)
  end

```

How do we want this to behave?

```elixir
defmodule Multicasting.BroadcasterReceiverTest do
  use ExUnit.Case
  alias Multicasting.{BroadcasterReceiver, ExpiringRegistry}

  describe "registering incoming hosts" do
    test "other hosts are registered" do
      BroadcasterReceiver.handle_info(
        {:udp, nil, {10, 20, 30, 40}, 49_002, "multitastic:somehost"},
        %{}
      )

      assert :multicast_host_registry
             |> ExpiringRegistry.registrations()
             |> Enum.any?(fn
               {"somehost", {10, 20, 30, 40}} -> true
               _ -> false
             end)
    end

    test "does not register this host as an entry" do
      {:ok, host} = :inet.gethostname()
      host = List.to_string(host)

      BroadcasterReceiver.handle_info(
        {:udp, nil, {10, 20, 30, 50}, 49_002, "multitastic:#{host}"},
        %{}
      )

      refute :multicast_host_registry
             |> ExpiringRegistry.registrations()
             |> Enum.any?(fn
               {^host, _} -> true
               _ -> false
             end)
    end
  end
end
```

```elixir
  # in  Multicasting.BroadcasterReceiver
  def handle_info({:udp, _port, ip, _port_number, @message_prefix <> hostname}, state) do
    Multicasting.Tick.tick(:broadcaster_receiver_tick)

    if hostname != this_hostname() do
      ExpiringRegistry.register(:multicast_host_registry, hostname, ip)
    end

    {:noreply, state}
  end

  defp this_hostname do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end
```

And for convenience.

```elixir
defmodule Multicasting do
  def registered_peers do
    Multicasting.ExpiringRegistry.registrations(:multicast_host_registry)
  end
end
```

Now you can [clone the repository](https://github.com/paulanthonywilson/otp-multicast-example) and (assuming you have Docker) run `./bin/docker-run.sh` in a few terminals. You can see the peer registrations in the repl.

```elixir
iex(1)> Multicasting.registered_peers
[{"84b3e8482d68", {172, 17, 0, 3}}, {"3383782fbd39", {172, 17, 0, 4}}]
```

Try shutting down the peers, and waiting 35 seconds. The registrations should disappear.


---

An Elixir Forum thread for this post is [here](https://elixirforum.com/t/elixir-blog-post-test-driving-otp-creating-a-registry-with-expiring-entries/38278), if have a question or criticism.

--- 

[^1]: pandemic reference not intended
[^2]: as in changing code, without affecting its behaviour
[^3]: our registry is unique, but some are started with duplicate keys.
[^4]: obviously there's typespecs and documentation missing, but they are absent to reduce the size of the code embedded in this post.