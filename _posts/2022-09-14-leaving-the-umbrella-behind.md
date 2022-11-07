---
layout: post
title: Leaving the umbrella behind
date: 2022-09-14 15:26:54 +0100
author: Paul Wilson
categories: elixir
---

I got into programming Elixir somewhere around 2013. (I'm not great with dates but I had a check of some projects on Github). Since I found out about them, every project I have initiated has been an [Umbrella Project](https://elixir-lang.org/getting-started/mix-otp/dependencies-and-umbrella-projects.html#umbrella-projects); for the past few years, though, I do seem to be the only person who likes Umbrellas[^1].

I have noticed that all projects that I've been brought in to work on are Flat[^2], that I never see example code for Umbrellas (eg in deployment tutorials), and that there are occasional negative (but non-specific) negative comments about them on Elixir Forum. The only two blog posts that I could find that decry Umbrellas are [Gregg Mefford's Nerves one introducing Poncho Apps](https://embedded-elixir.com/post/2017-05-19-poncho-projects/) and [The problem with Elixir Umbrella Apps, by Jack Marchant](https://www.jackmarchant.com/the-problem-with-elixir-umbrella-apps). I find neither of those at all convincing, for reasons I describe later. This had me wondering if it were me that was out of touch, or whether every other Elixir programmer was wrong.

![Principal Skinner Out of Touch Meme](/assets/skinner_out_of_touch.jpg)

So I [asked on Elixir Forum](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585) and got some answers that I did not like.

Turns out that I have been looking at this the wrong way. Rather than there being strong reasons that Umbrellas are bad, people do not experience much benefit from them. At the same time Umbrella Projects do add a certain amount of overhead and tooling issues. People do not find that the costs versus benefits lands on the side of Umbrellas. Reluctantly, I can see their point.

## Why I like Umbrella Projects in the first place

At Nordic Ruby 2011 [Tom Preston-Werner](https://en.wikipedia.org/wiki/Tom_Preston-Werner) crammed a lot of good stuff into his 30 minute talk[^3], including the idea of separating out units of functionality in a (Ruby / Ruby on Rails) application _as if_ they were [Ruby Gems](https://en.wikipedia.org/wiki/RubyGems) even if it would never make sense to extract them into a _gem_. I loved that concept; it introduced a very clean way of seperating different areas of the domain[^4]. Unfortunately when I came to try out the idea, the pain of going against the grain in Rails Apps proved too much.

When I discovered Umbrella Projects in Elixir I was delighted. They _just worked_ out of the box to give neat seperation of concerns and enforcing directionality in intra-app dependencies. Each app is structured as if it were a separate [hexicle](https://twitter.com/paulanthonywils/status/1050442755833556992), making them beautifully separated. I love the neatness of keeping all the related files, even the tests, closely together.

As mentioned, when I have had the choice I've been (mostly) happily using Umbrellas ever since, and bemoaning their absence when working on _Flat Projects_.

## Wrong reasons that Umbrella Projects are bad

People have made a number of arguments against Umbrellas, some of which do not stack up.

### Configuration and Ponchos

Ponchos were introduced, or at least popularised, in the previously mentioned [very short Nerves Post](https://embedded-elixir.com/post/2017-05-19-poncho-projects/). To save you a click the issue identified was that Umbrella Projects default to pointing their config to `config/config.exs`, and that contained

```elixir
import_config "../apps/*/config/config.exs"
```

Configuration was loaded from all the Umbrella Projects in undefined order.

While the objection is no longer valid as these days Umbrella Projects default to using a single configuration, at the root of the Umbrella, it was not valid in 2017 either. Changing the root `config.exs` to do something different, such as using configuration at the root or loading any application configuration in a defined order was always trivially easy. Just so something is generated a certain way does not mean you can't change it.

Poncho apps are simply standalone Elixir apps, that are linked using the `path` attribute in the dependencies eg (`{:myappdep, path: "../myappdep"}`), with a single designated "app" used to build releases (/ Nerves firmware).

I have not heard this, but an argument could be made for a slight advantage of Ponchos over an Umbrella: dependencies are compiled in the `prod` Mix.env() regardless of the environment being used to compile the main app. This makes it even more like using a [hexicle](https://twitter.com/paulanthonywils/status/1050442755833556992), for example `test/supprt` that is only compiled in `test` could not be shared between applications.

If you are definitely planning to extract and publish applications as separate [hexicles](https://twitter.com/paulanthonywils/status/1050442755833556992), a Poncho-like structure _might_ be the way to go.

### That other Blog post

The (previously mentioned) [other anti-Umbrella post](https://www.jackmarchant.com/the-problem-with-elixir-umbrella-apps) that I could find has also has some pretty week arguments mostly consisting of untrue or unsupported statements:

> if everything is deployed together you can still technically access modules that are technically circular dependencies, which kind of breaks the separation concept.

Well, no. If you explicitly create a cyclic dependency in the `mix.exs`'s then the compilation will fail

```sh
** (Mix) Could not sort dependencies. There are cycles in the dependency graph
```

Technically you _could_ call from one app to another without explicitly making the other a dependency but you would have to ignore a **massive** warning, which _would_ make you a fool.

> it will most likely slow you down the more code you add as the boundaries become more brittle and blurred

Unless you are the kind of fool who ignores massive warnings, then the Umbrella Project related boundaries will remain crisp.

> Umbrella child apps are intended to be created as a way to deploy each of them separately

Intended? Intended by whom? You could[^5] create separate [Elixir releases](https://elixir-lang.org/getting-started/mix-otp/config-and-releases.html#releases) to deploy different parts of an Umbrella separately, but I have seen no evidence that is their purpose. The blog post contains no links, or supporting arguments, that back up that statement.

If you create a new Phoenix app with `mix new myapp --umbrella` then you get two applications which can not be deployed separately in any way that makes sense, which makes me extra-sceptical about this apparent intention of Umbrella Projects.

> I can guarantee moving into an umbrella app configuration, retrofitting on an existing app is the easier option than consolidating child apps

That's one of those statements that is hard to argue with, because it is unsupported. In my experience it is much easier to consolidate separated code than to separate consolidated code, because the dependencies in the latter invariably need a lot of unpicking.

### Umbrellas do not make sense for code organisation

> OTP applications are a runtime and deployment concern, not a code separation tool, so it doesn’t even make sense to use an umbrella for code organization in the first place

From [this Elixir Forum response](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/11?u=paulanthonywilson).

That specific point[^6] had me thinking for a while, because I use Umbrellas entirely for code organisation and never[^7] worry about separate deployments or starting up independently from other _applications_. But I reflected that, any _Mix project_ an _app_ in an Umbrella Project does not even need to be an _application_ with its own supervision tree. Again, I don't think the "not for code organisation" makes sense in itself.

## Valid reasons not to use Umbrellas

These are all covered in [that Elixir Forum thread](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585), but boil down to the advantages being few and achievable by other means while the disadvantages are several and impair both [ease and joy](http://www.exampler.com/blog/2007/05/16/six-years-later-what-the-agile-manifesto-left-out/http://www.exampler.com/blog/2007/05/16/six-years-later-what-the-agile-manifesto-left-out/) in the programming.

[![Agit Prop Style poster of raised chlenched fists with one ringing a bell. The title is "Discipline Skill Ease Joy"](/assets/disciplineskilleasejoy.jpg)](http://www.exampler.com/ease-and-joy/)

### Poor tooling support

This can be quite a headache. Poor support for `mix xref` was cited a few times, eg [here](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/9?u=paulanthonywilson)

A telling quote is

> Also the fact that you have to append “in an umbrella app” whenever you ask someone for advice on fixing your weird bug should be a sign that something is off from the start.

From [here](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/11?u=paulanthonywilson)

Something else that has also irritated me:

> various paths that are printed by mix tasks (e.g. test IIRC) aren’t “clickable” in vscode (I couldn’t click to open the file in the editor), because the printed paths are missing the apps/myapp/ prefix. I found this extremely annoying and disruptive.

[From here](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/18?u=paulanthonywilson)

Supporting Umbrella Projects must be a pain for tool maintainers that need to care about the structure of your files, both when writing the code and testing the different scenarios. It is no wonder that support for Umbrellas is missing, or buggy. (I think that both my PRs to Nerves have been for Umbrella support).

A related issue not brought up (except by me) is that following tutorials needs an extra layer of translation for Umbrella Projects, eg in the [Fly IO Phoenix Deployment documentation](https://fly.io/docs/elixir/getting-started/).

### More directories to navigate, and more files

> they create an extra layer of indirection in your file paths (apps/ directory)

[here](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/3?u=paulanthonywilson)

More directories can be a pain to navigate, especially if you are using a navigation tree. Having to be in different directories to perform different mix tasks can also be a bit of a headache.

### More code, slower build

> about 2k LOC less, due to removal of the repetitive boilerplate across subprojects

[here, on moving a project from Umbrella to flat](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/18?u=paulanthonywilson)

Another problem with the multiple "apps" is the repeated identical file names. I have edited the wrong `mix.exs` file, for instance, on several occasions.

Also, from the same post,

> faster test and build times

Having not worked on huge Umbrealla Projects this is not something I have noticed. Unfortunately there are not timings, but [Saša Jurić says that the difference is noticeable](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/22?u=paulanthonywilson).

### There are better ways to achieve the same objectives

> A better solution is to just be unafraid to make top level namespaces in the main app (like how Phoenix creates MyApp and MyAppWeb)

[from here](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585/3?u=paulanthonywilson)

I like that.

> Tools like [Saša Jurić's Boundary] offer a better way to tackle the “I don’t want code from this module to be called by this other module” problem in a saner way that doesn’t break most of the tools out there.

I remember taking a look at [Boundary](https://hexdocs.pm/boundary/Boundary.html) a while back, but did not try it for some reason. I think it was a bit early-doors at the time, and I was satisfied with Umbrellas. It seems pretty solid now, and I will definitely try it out in future.

## In Conclusion

> The man who never alters his opinion is like standing water, and breeds reptiles of the mind.

[William Blake, The Marrige of Heaven and Hell](https://www.gutenberg.org/cache/epub/45315/pg45315.txt)

I am sufficiently convinced to take a step back from Umbrella Projects, despite using them for many years, and try some different approaches to get the same separation of concerns and dependency directionality. I am grateful to the participants in the [Elixir Forum thread](https://elixirforum.com/t/what-s-wrong-with-umbrella-apps/49585?u=paulanthonywilson) for the enlightening discussion.

---

[^1]: Umbrella Projects, that is. I prefer a waterproof jacket to an actual umbrella, especially here in windy Scotland.

[^2]: I think I may have made up the term _Flat App_, for apps which are not Umbrellas, but I need to call them something and it's not going to be _Non-Umbrella Projects_, so don't start with that. _Normie Apps_ might be an ok term. (It's that field hockey vs ice hockey thing.)

[^3]: There's no full video of Nordic Ruby talks that I can find. There's just [this flavour of the conference video](https://vimeo.com/27142345). Tom appears around at 2`6". There's also a brief extract of one of the best conference talks I've seen, Chad Fowler on "Legacy Systems" at 1'13. A younger, thinner, version of me makes a brief appearance at 5'33".

[^4]: Which was (is?) sorely lacking in Ruby on Rails.

[^5]: I wouldn't

[^6]: The rest of that post, and contributions from the author, does contain some great arguments; this is more of an aside, I think.

[^7]: Never, apart from some experimental Nerves work with different interacting components. Also a Nerves + Server side deployment which I kept in a single Umbrella, but probably would not do again.
