---
layout: post
title: "Elixir mock (test double) testing seams: a modest proposal"
date: 2023-03-24 10:56:13 +0000
author: Paul Wilson
categories: elixir tdd mocks
---

The José Valim approved (tm) way of introducing mocks[^1] into Elixir is through [injecting implementations of explicit contracts defined by behaviours](https://dashbit.co/blog/mocks-and-explicit-contracts). José and pals crystallised this approach with the popular [Mox hexicle](https://hexdocs.pm/mox/Mox.html).

The standard way of injecting the mock or real implementation into the code under test is by passing modules around by some method. The implementation module is typically loaded from _application config_ which can be tailored to the _mix environment_. I find this approach somewhat dissatisfying as the _module_ being passed around is just an atom containing no metadata.

Apart from a general lack of tidiness, this provides a route for errors to slip through code which passes all the test. I do have a suggestion which would help. It will involve code that looks like this

```elixir
  @implementation if Mix.env() == :test, do: MockCatFactsApi, else: RealCatFactsApi
  defmacro __using__(_) do
    quote do
      alias unquote(@implementation), as: CatFactsApi
    end
  end
```

You may not be attracted by that, but please bear with me. You may, at least, learn something surprising about feline collar bones. (I don't believe the thing about Newton, though.)


### The usual approach

Let's get some cat facts using the standard method of implementation injection. The full implementation is [here](https://github.com/paulanthonywilson/cat_facts).

We'll define a behaviour as a testing seam

```elixir
defmodule CatFacts.CatFactsApi do
  @callback get_facts(path :: String.t(), finch_pool :: atom) ::
              {:ok, Finch.Response.t()} | {:error, Exception.t()}
end
```

And we're going to drive out our behaviour with tests.

```elixir
defmodule CatFactsTest do
  use ExUnit.Case
  import Mox
  setup :verify_on_exit!

  test "Can get a fact" do
    expect(MockCatFactsApi, :get_facts, fn "fact", CatFinch ->
      {:ok,
       %Finch.Response{
         body: "{\"fact\":\"Cats are really dogs in disguise.\",\"length\":33}",
         status: 200
       }}
    end)

    assert {:ok, "Cats are really dogs in disguise."} == CatFacts.fact()
  end

  # After this we will want to test out verious error and edge conditions but 
  # we'll leave those out of here for brevity
end
```

Inject mock and real implementations, with the private function `get_cat_facts_api/0`.


```elixir
defmodule CatFacts do
  def fact do
    "fact"
    |> cat_facts_api().get_facts(CatFinch)
    |> handle_response()
  end

  defp cat_facts_api do
    Application.get_env(:cat_facts, CatFacts.CatFactsApi, CatFacts.RealCatFactsApi)
  end

  # handle_response/2 ommited for brevity
end
```

If we define the `mock` (say in "test/support/mocks.ex") and configure it for test then our tests will run.

```elixir
Mox.defmock(MockCatFactsApi, for: CatFacts.CatFactsApi)
```

```elixir
# config/config.exs
import Config

import_config "#{config_env()}.exs"
```

```elixir
# config/test.exs
import Config

config :cat_facts, CatFacts.CatFactsApi, MockCatFactsApi
```

```
cat_facts (main) $ mix test
....
Finished in 0.02 seconds (0.00s async, 0.02s sync)
4 tests, 0 failures

Randomized with seed 566481
```

Nearly there. We also need an actual implementation.

```elixir
defmodule CatFacts.RealCatFactsApi do
  @cat_facts_base "https://catfact.ninja"

  def get_facts(path, finch_pool) do
    url = Path.join(@cat_facts_base, path)

    :get
    |> Finch.build(url)
    |> Finch.request(finch_pool)
  end
end

```

Let's get a cat fact!

```
Erlang/OTP 25 [erts-13.2] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit]

Interactive Elixir (1.14.3) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> CatFacts.fact()
{:ok,
 "The cat's clavicle, or collarbone, does not connect with other bones but is buried in the muscles of the shoulder region. This lack of a functioning collarbone allows them to fit through any opening the size of their head."}
```

&nbsp;

I did not know that about cat's clavicles.

So, this is all great, but your company's Star Chamber of Staff Engineers have just decreed a new coding standard: api functions must be alliterative. As the annual performance review is looming, we rush to rename. 

### The code change 

```elixir
defmodule CatFacts.CatFactsApi do
  @callback fetch_fun_feline_facts(path :: String.t(), finch_pool :: atom) ::
              {:ok, Finch.Response.t()} | {:error, Exception.t()}
end
```

```elixir
defmodule CatFactsTest do
  use ExUnit.Case
  import Mox
  setup :verify_on_exit!

  test "Can get a fact" do
    expect(MockCatFactsApi, :fetch_fun_feline_facts, fn "fact", CatFinch ->
      {:ok,
       %Finch.Response{
         body: "{\"fact\":\"Cats are really dogs in disguise.\",\"length\":33}",
         status: 200
       }}
    end)

    assert {:ok, "Cats are really dogs in disguise."} == CatFacts.fact()
  end

  # still taking the other tests as read
end
```


```elixir
defmodule CatFacts do
  # ...
  def fact do
    "fact"
    |> cat_facts_api().fetch_fun_feline_facts(CatFinch)
    |> handle_response()
  end

  # etc...
end
```

```
cat_facts (main) $ mix test
Compiling 2 files (.ex)
....
Finished in 0.01 seconds (0.00s async, 0.01s sync)
4 tests, 0 failures
```

Phew! We're done. Except, oh no! There's an error in production.

```
cat_facts (main) $ iex -S mix
Erlang/OTP 25 [erts-13.2] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [jit]

Compiling 4 files (.ex)
Generated cat_facts app
Interactive Elixir (1.14.3) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> CatFacts.fact()
** (UndefinedFunctionError) function CatFacts.RealCatFactsApi.fetch_fun_feline_facts/2 is undefined or private
    (cat_facts 0.1.0) CatFacts.RealCatFactsApi.fetch_fun_feline_facts("fact", CatFinch)
    (cat_facts 0.1.0) lib/cat_facts.ex:9: CatFacts.fact/0
    iex:1: (file)
```

Obviously you, perceptive reader, have already spotted both errors:

1. We (ok I) forgot to  add `@behaviour CatFacts.CatFactsApi`
2. And we did not rename  `CatFacts.get_facts/1`

You spotted it but the compiler did not; there were no warnings. Dialyzer can not help you either. The most you could say about `CatFacts.cat_facts_api/1` is that it returns an atom; that is returns an atom representing a module that implements a specific behaviour is an unsayable concept.

```elixir
  # not very helpful
  @spec cat_facts_api :: atom()
```

You may be thinking that this is a contrived example: this is not the kind of error that would be written and get past a code review.

<p><a href="https://xkcd.com/908/"><img src="/assets/the_cropped_cloud.png" alt="Last two frames cropped from XKCD 908, The Cloud. Blackhat is sitting at a computer and cueball is asking questions.
Cueball: Should the cord be stretched across the room like this?
Blackhat: Of course. It has to reach the server and the server is is over there.
Cueball: What if someone trips on it?
Blackhat: Who would want to do that? It sounds unpleasant.
Cueball: Uh. Sometimes people do stuff by accident.
Blackhat: I don't think I know anybody like that.
" title="Last two frames cropped from XKCD 908, The Cloud. Blackhat is sitting at a computer and cueball is asking questions.
Cueball: Should the cord be stretched across the room like this?
Blackhat: Of course. It has to reach the server and the server is is over there.
Cueball: What if someone trips on it?
Blackhat: Who would want to do that? It sounds unpleasant.
Cueball: Uh. Sometimes people do stuff by accident.
Blackhat: I don't think I know anybody like that."></a></p>

Ok, Blackhat, my experience is a little different. I definitely found many examples of `@behaviour` being missed in a particular company's codebase.

This kind of error can happen. It would be lovely if we could at least get some kind of compiler warning when renaming (or function arity changing) goes wrong. Read on to find out how we can.

### The alternative approach

```elixir
defmodule CatFacts.CatFactsApi do
  @callback fetch_fun_feline_facts(path :: String.t(), finch_pool :: atom) ::
              {:ok, Finch.Response.t()} | {:error, Exception.t()}

  defmacro alias do
    implementation = Application.get_env(:cat_facts, __MODULE__, CatFacts.RealCatFactsApi)
    quote do
      alias unquote(implementation), as: CatFactsApi
    end
  end
end
```

```elixir
defmodule CatFacts do
  require CatFacts.CatFactsApi
  CatFacts.CatFactsApi.alias()

  def fact do
    "fact"
    |> CatFactsApi.fetch_fun_feline_facts(CatFinch)
    |> handle_response()
  end

  # etc...
end
```

The tests still run.

```
cat_facts (main) $ mix test
Compiling 3 files (.ex)
....
Finished in 0.01 seconds (0.00s async, 0.01s sync)
4 tests, 0 failures
```

But if we compile for `dev` or `prod` we get a warning. This should be a welcome safety net, especially if your build server is configured to treat warnings as errors.

```
cat_facts (main) $ mix compile
Compiling 2 files (.ex)
warning: CatFacts.RealCatFactsApi.fetch_fun_feline_facts/2 is undefined or private
  lib/cat_facts.ex:13: CatFacts.fact/0
```

Incidentally, dialyzer is now similarly unimpressed

```

lib/cat_facts.ex:12:call_to_missing
Call to missing or private function CatFacts.RealCatFactsApi.fetch_fun_feline_facts/2.
________________________________________________________________________________
done (warnings were emitted)
Halting VM with exit status 2
```

There's still some room for improvement. 

* Having to `require CatFacts.CatFactsApi` before calling the `alias/0` macro is a bit awkward. My preference is to sidestep this a bit with `use`. 
* We're using `Application.get_env/3` at compile time but we can't use `Application.compile_env/3` inside a macro. We could use this with an attribute `@impl Application.compile_env(:cat_facts,  __MODULE__, CatFacts.RealCatFactsApi)` but ...
* We are always using one implementation in the `test` environment and another elsewhere. I do not consider that configuration. My preference is to explicitly state the implementations in the code rather than having to look in another file ("config/test.exs"). 


```elixir
defmodule CatFacts.CatFactsApi do
  @callback fetch_fun_feline_facts(path :: String.t(), finch_pool :: atom) ::
              {:ok, Finch.Response.t()} | {:error, Exception.t()}

  @implementation if Mix.env() == :test, do: MockCatFactsApi, else: CatFacts.RealCatFactsApi
  defmacro __using__(_) do
    quote do
      alias unquote(@implementation), as: CatFactsApi
    end
  end
end

```

```elixir
defmodule CatFacts do
  use CatFacts.CatFactsApi
  # etc ..
end
```

## Drawbacks

There are two potential drawbacks to the approach I am suggesting here:-

### Reduction in flexibility

This alternative approach needs the implementation switching to be happen at compile time. The standard approach allows for the implementation to be determined at runtime. This matters little when injecting mocks. It is possible you may want to use the pattern for other purposes, such as switching out an actual implementation in production controlled by a feature flag; in this case I would agree that something along the lines of passing modules around is still a reasonable approach.

### Reviewers

Asynchronous code reviews via pull requests have become ubiquitous over the last ten or so years. Combined with [FAANG](https://en.wikipedia.org/wiki/Big_Tech)-style performance reviews, one of the side effects is presure on developers to review quickly while being able to display their own knowledge and competence[^2].

Finding a macro in the code can be like catnip[^3] to a reviewing developer under those pressures. Without much thought they can block and say something to the effect of "This is over-engineering. You can replace these 3 simple lines of code with these other lines of code." If they are feeling particularly pompous they might just quote from the macro or [library guidelines](https://hexdocs.pm/elixir/1.12/library-guidelines.html#avoid-macros). 

If I have managed to persuade you to give this method of implementation-injection a shot, your ability to to actually do so may be limited by the social and power dynamics in your organisation.

## Advantages

### Better mistake cover from compiler or dialyzer warnings

I hope that I have already established this advantage. I should probably point out that the alternative approach will not let you know about forgotten `@behaviour` directives, but it will protect you from the consequences.

### Less bloated configuration

Large projects that make heavy use of `Mox` often end up massive "text.exs" files which are a headache to organise and maintain.

If something can be known at compile time and never changes between different physical environment (ie different developer's laptops, build servers, deployments) then I do not think that is configuration. If you can inline that to where it is used then you have made things simpler and more explicit.

It might look odd to you (and unfortunately your reviewers) at first. That is because you (and they) are not used to it.



## More cat facts

While were here, and having fixed the implementation ...

```elixir
iex(7)> CatFacts.fact()
{:ok,
 "When a cat drinks, its tongue - which has tiny barbs on it - scoops the liquid up backwards."}
iex(8)> CatFacts.fact()
```

Wait? What does scooping up liquid backwards even mean? Let's try another one.

```elixir
iex(16)> CatFacts.fact()
{:ok,
 "Isaac Newton invented the cat flap. Newton was experimenting in a pitch-black room. Spithead, one of his cats, kept opening the door and wrecking his experiment. The cat flap kept both Newton and Spithead happy."}
```

Citation needed and I doubt it, though I do feel better having read that.

Even if true, it still would not not be my favourite cat fact. My favourite is one that I read on an information board at [The Highland Wildlife Park](https://www.highlandwildlifepark.org.uk): the decline in Scottish wildcat numbers was reduced during the First World War because conscription reduced the gamekeeper population.

![Photo of information board: "The prolonged tragedy of WW1 calls up gamekeepers leading to a decline in wildcat persecution](/assets/wild_cat_ww1.png)


PS Just saw another cat fact in the news as I was writing this: approval for releasing [Scottish wildcats being into The Cairngorms has been granted](https://www.bbc.co.uk/news/uk-scotland-highlands-islands-65065167) from The Highland Wildlife Park. 


--- 

[^1]: There's some awkward terminology around all this which is probably not important. I should really say _test double_ but I've always found that an awkward phrase. See [XUnit patters](http://xunitpatterns.com/Mocks,%20Fakes,%20Stubs%20and%20Dummies.html) for definitions. It is common in Elixir Land (as other places) to use _Mock_ for _Test Doubles_ so I will just stick with that here; being more correct would also be more confusing.

[^2]: It's a hard trap to avoid. I've been meaning to write something about reviewing more effectively but I doubt I could better [Dan Munckton](https://cultivatehq.com/posts/how-to-be-a-kinder-more-effective-code-reviewer/) or [Chelsea Troy](https://chelseatroy.com/2019/12/18/reviewing-pull-requests/).

[^3]: Cat fact.