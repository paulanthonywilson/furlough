---
layout: post
title: Blogging with LiveBook
date: 2021-06-06 10:07:59 +0100
author: Paul Wilson
categories: elixir
---

Last week I wrote [a post on killing OTP processes]({% post_url 2021-05-31-the-many-and-varied-ways-to-kill-an-otp-process %}), which was also a [LiveBook page](https://github.com/elixir-nx/livebook). The process for embedding LiveBook in a [Jekyll](https://jekyllrb.com) blog was straightforward, if not entirely satisfactory. If you're curious, or want to try it, here's my current setup for this:

## Directory for LiveBook pages

The standard Jekyll setup has a directory `_posts` for your blog posts. (The engine processes the contents of the directory to populate the `_site_` directory with your posts.). I created a [livebook](https://github.com/paulanthonywilson/furlough/tree/c133d351989adf4ca7a73e17422d74d4a2318da3/_posts/livebook) directory under posts to house my LiveBook pages[^1].

## Publishing the LiveBook page as a blog post.

Once I've got my LiveBook page in `_posts_/livebook`, I still need to get it into the blog. A Jekyyll post needs some headers (not LiveBook friendly) and the content. To get the page embedded, I created new blog post and used the [`include_relative` tag](https://jekyllrb.com/docs/includes/) to embed the page. The entire previous blog post (source  [here](https://github.com/paulanthonywilson/furlough/blob/c133d351989adf4ca7a73e17422d74d4a2318da3/_posts/2021-05-31-the-many-and-varied-ways-to-kill-an-otp-process.md)) is thus


{% raw %}
```
---
layout: post
title: The many and varied ways to kill an OTP Process
date: 2021-05-31 11:02:22 +0100
author: Paul Wilson
categories: elixir otp
---

{% include_relative livebook/varied-ways-to-kill.livemd %}

```
{% endraw %}

## Dealing with the double header

Jekyll adds the post title as a `h1` header. LiveBook also creates a `h1` header for the page title, so now there's got two titles. I guess I could fix this by post-processing the LiveBook page, or doing fancy stuff with Jekyll but as no other posts should have `h1` in content I just hid it in the (s)css ([source](https://github.com/paulanthonywilson/furlough/blob/c133d351989adf4ca7a73e17422d74d4a2318da3/_sass/minima/_layout.scss#L232-L238)).

```scss
.post-content {
  h1 {
    display: none;
  }
}
```

Admittedly, it's a bit of a hack and probably mildly dubious from an accessibility point of view

## Pointing the Livebook server to the right place

LiveBook servers can be kicked off from any directory and browser to pick up or save pages to any other directory. For convenience, though, I created a [shell script](https://github.com/paulanthonywilson/furlough/blob/master/bin/live-blog) in this blog's `bin` directory for launching a server pointing in roughly the right direction.

```sh
#!/usr/bin/env sh

set -e

ROOT_PATH=`dirname $0`/../_posts/livebook

livebook server --root-path=$ROOT_PATH
```

## Satisfaction

The LiveBook embedded post looks ok, and fits with the rest of the posts in this blog. (Obviously it all could look a lot better than the basic theme, but that kind of thing is beyond my capabilities).

Of course, the blog post is not directly executable, though someone could download it from [here](https://github.com/paulanthonywilson/furlough/blob/master/_posts/livebook/varied-ways-to-kill.livemd) and execute it locally.

It would be a lot better if the output of executing all the code in the page could be somehow captured and published, though I can think of all kinds of ways that this would not be straightforward. I may take a look sometime, though.

---

[^1]: *cough* I guess LiveBook _page_ at the time of writing; there's only one.
