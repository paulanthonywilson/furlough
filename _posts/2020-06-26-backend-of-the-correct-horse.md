---
layout: post
title: Backend of the correct horse
date: 2020-06-26 13:28:05 +0100
author: Paul Wilson
categories: log elixir terraform
---

This week I have been mainly iterating (aka going round in circles) on application deployment, but I did [say that I would talk a bit about the backend]({% post_url 2020-06-18-memorable-password-generation-with-liveview %}#backend---generating-the-passwords) of the [memorable password generator](https://github.com/paulanthonywilson/correct-horse-elixir).

## It's just an ETS table

On reflection, there is not much to say on the backend. It is essentially an ETS table. It is owned by a _GenServer_, [`WordList`](https://github.com/paulanthonywilson/correct-horse-elixir/blob/153ddd7bcfccdf09f05449cec2f54c6b5694ee2b/apps/correcthorse/lib/correcthorse/words/word_list.ex).

`WordList` is initialised with a reference (for access) and an `Enum` containing all the words. In production [this is a `FileStream`](https://github.com/paulanthonywilson/correct-horse-elixir/blob/main/apps/correcthorse/lib/correcthorse/application.ex#L20) to a text list of just under 5,000 common words which I picked up from various places. For testing it is just a [short list of words](https://github.com/paulanthonywilson/correct-horse-elixir/blob/main/apps/correcthorse/test/correcthorse/words/word_list_test.exs#L7).

`WordList`'s _GenServer_ creates the table in its `init/1`.

```elixir
 def init({reference, words}) do
    table = :ets.new(reference, [:named_table, :set, read_concurrency: true])
    {:ok, {table, words}, {:continue, :add_words}}
  end
  ```

  Note that:

  * It's a named table and its name is the reference.
  * The default table setting is `protected` meaning that only the owning process can write to the table but, crucial for concurrent access, any process can read.
  * It is read concurrent


It's also a set, meaning the keys are unique, but that is not  important in this case.

Reading the contents into the table carries on in a `handle_continue`

```elixir
def handle_continue(:add_words, {table, words}) do
    words
    |> Stream.map(&String.trim/1)
    |> Stream.with_index()
    |> Enum.each(fn {w, i} -> :ets.insert(table, {i, w}) end)

    {:noreply, {}}
end
```

The words a trimmed to get rid of the trailing `\n` that comes in the filestream.  The word is added to the the table with an index as the key.

The `WordList` module provides a convenience method to retrieve a word from the table by  its table reference, and word index, `word_at/2`.

```elixir
@spec word_at(word_list_ref(), pos_integer()) :: {:error, :invalid_index} | {:ok, String.t()}
def word_at(reference, index) do
  case :ets.lookup(reference, index) do
    [{^index, word}] -> {:ok, word}
    _ -> {:error, :invalid_index}
  end
end
```

Not that this takes place in the _caller's process_, allowing concurrent access. If there had been a `GenServer.call` to the owning process then this would cause a bottleneck.

The size of the table is easy enough to get:

```elixir
@spec size(word_list_ref()) :: pos_integer()
def size(reference) do
  :ets.info(reference, :size)
end
```

So, getting a random word is also super easy:

```elixir
@spec random_word(word_list_ref()) :: String.t()
def random_word(reference) do
  size = size(reference)
  index = :rand.uniform(size) - 1
  {:ok, word} = word_at(reference, index)
  word
end
```

Other bits and pieces of the backend involve [getting a list of random words matching the minimum words and characters specifications](https://github.com/paulanthonywilson/correct-horse-elixir/blob/153ddd7bcfccdf09f05449cec2f54c6b5694ee2b/apps/correcthorse/lib/correcthorse/password.ex#L18)) and turning that list into [a password with the decoration and separation options](https://github.com/paulanthonywilson/correct-horse-elixir/blob/153ddd7bcfccdf09f05449cec2f54c6b5694ee2b/apps/correcthorse/lib/correcthorse/password.ex#L45).

## Iterating on the deployment

I explored using [packer](https://packer.io) to creat an [AMI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) containing the release on top of a basic image. It turned out to be both easy and a poor approach: it is painfully slow and uses up lots of EBS storage.

I went back to minimal provisioning with Terraform. Right now I'm using the [file provisioner](https://www.terraform.io/docs/provisioners/file.html) to [get a gzipped tar of the release onto the box](https://github.com/paulanthonywilson/correct-horse-elixir/blob/153ddd7bcfccdf09f05449cec2f54c6b5694ee2b/deploy/terraform/main.tf#L153-L156). The [remote exec provisioner](https://www.terraform.io/docs/provisioners/remote-exec.html) then [untars and starts](https://github.com/paulanthonywilson/correct-horse-elixir/blob/153ddd7bcfccdf09f05449cec2f54c6b5694ee2b/deploy/terraform/main.tf#L158-L164) the service. 

## Rust meetup

On Thursday evening I attended the remote [Edinburgh Rust meetup](https://www.meetup.com/rust-edi/), which was an account of a setup to automatically irrigate tomatoes in a greenhouse. I enjoyed the talk, though I have only dabbled in Rust. Obviously I would have used [Nerves](https://www.nerves-project.org) for such a project, but Rust was a fine choice. Neil's code is [here](https://github.com/neilgall/pirrigator).

An interesting snippet was using Rust targeted at [Web Assembly](https://webassembly.org) for graphing sensor information. Rust for front-end web visuals seems to be a valuable emerging niche for the language.
