---
layout: post
title: Content Security Policy configuration (in Phoenix)
date: 2021-02-26 13:53:07 +0000
author: Paul Wilson
categories: elixir phoenix security
---

_This post is about setting a [Content Security Policy](https://content-security-policy.com), specifically in Phoenix. But being about a response header it is probably more widely applicable._

---- 

The other day I ran [sobelow](http://hexdocs.pm/sobelow/) to check the security of a [project](https://github.com/paulanthonywilson/mcam) I've been working on. It was happy enough, apart from suggesting that I added a [Content Security Policy](https://content-security-policy.com). Sobelow's documentations says

> When it comes to CSP, just about any policy is better than none. If you are unsure about which policy to use, the following mitigates most typical XSS vectors:

```elixir
plug :put_secure_browser_headers, 
    %{"content-security-policy" => "default-src 'self'"}
```

Fair enough, I thought, and opened that can of worms. Firing up by development environment and pointing Safari to _http://localhost:400_   , I found it did not work. Opening up the browser console I saw

```
EvalError: Refused to evaluate a string as JavaScript because 'unsafe-eval' 
  is not an allowed source of script in the following Content Security Policy 
  directive: "default-src 'self'".
```

This seemed to be an issue with with Webpack and development mode. One option[^1] would be to not have a Content Security Policy in `dev` mode, but it seems better to keep `dev` fairly close to `prod`, so we can work out issues on our own machines first. Only in `dev` lets get unstuck and allow `unsafe-eval`.

```elixir
  @content_security_policy (case Mix.env do
    :prod  -> "default-src 'self'"

    _ -> "default-src 'self' 'unsafe-eval'"

  end)

  pipeline :browser do
    # other browser plugs here
    plug(:put_secure_browser_headers, %{"content-security-policy" => @content_security_policy})
  end

```

Now Safari gives us:

```
Refused to connect to ws://localhost:4000/live/websocket? ...  
  because it appears in neither the connect-src directive nor the 
  default-src directive of the Content Security Policy
```

Oh no, our [LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html) WebSocket is being blocked by Safari. (Chrome does not block the WebSocket, which does emphasise the importance of cross-browser testing.)

Checking [the documentation](https://content-security-policy.com/#source_list) it looks like we need to add an explict entry in a `connect-src` directive. First let's find our server host from configuration. (For the purposes of this post I've added a Content Security Policy to the example [Starjumps](https://github.com/paulanthonywilson/binary-websockets-example) application.)

```elixir
# in the router.ex
  @host :starjumps
        |> Application.fetch_env!(StarjumpsWeb.Endpoint)
        |> Keyword.fetch!(:url)
        |> Keyword.fetch!(:host)
```

Now we can allow WebSockets 

```elixir
  @content_security_policy (case Mix.env do
    :prod  -> "default-src 'self';connect-src wss://#{@host};"

    _ -> "default-src 'self' 'unsafe-eval';connect-src ws://#{@host}:400"

  end)
```

In both the example [Starjumps](https://github.com/paulanthonywilson/binary-websockets-example) project and my actual project, I am using `URL.createObjectURL()` in Javascript to load images (from a WebSocket) into a HTML `img` element. (I wrote about all that [here]({% post_url 2021-02-19-binary-websockets-with-elixir-phoenix %}).) 

This now leads to this kind of browser error:

```
[Error] Refused to load blob:http://localhost:4000/e672fb22-5944-49b8-82d6-fb128d793a80 
  because it appears in neither the img-src directive nor the default-src
  directive of the Content Security Policy.
```

We can solve that with adding `blob:` (with the colon) to an `img-src` directive.

```elixir
  @content_security_policy (case Mix.env do
    :prod  -> "default-src 'self';connect-src wss://#{@host};img-src 'self' blob:;"

    _ -> "default-src 'self' 'unsafe-eval';connect-src ws://#{@host}:*;img-src 'self' blob:;"
  end)
```

Note that we also need to add `self` to `img-src` if we want to be able to load normal images.

And that is us done. Unless you want to use (say) [Phoenix's Live Dashboard](https://github.com/phoenixframework/phoenix_live_dashboard/).


![Screenshot of a broken live dashboard](/assets/bad_dashboard.png)

Urgh, that's not great. Our browser error console is telling us

```
Refused to apply a stylesheet because its hash, its nonce, or 'unsafe-inline' 
  appears in neither the style-src directive nor the default-src directive of 
  the Content Security Policy.

Refused to load data:image/png;base64, iVBORw0KGg... because it does not appear
 in the img-src directive of the Content Security Policy.

Refused to execute a script because its hash, its nonce, or 'unsafe-inline' 
  appears in neither the script-src directive nor the default-src 
  directive of the Content Security Policy.
```

Assuming we only want to load the dashbaord in `dev` mode[^2] then we can solve the issues with `unsave-inline` and allowing `data:` as well as blob for `image:`. 

```elixir

  @content_security_policy (case Mix.env do
    :prod  -> "default-src 'self';connect-src wss://#{@host};img-src 'self' blob:;"

    _ -> "default-src 'self' 'unsafe-eval' 'unsafe-inline';" <>
        "connect-src ws://#{@host}:*;" <>
        "img-src 'self' blob: data:;" <>
  end)
```

We also then run into a font issue

```
Refused to load data:font/woff2;base64,d09GMgABAAAA .... 
  because it appears in neither the font-src directive nor the default-src 
  directive of the Content Security Policy.
```

Solveble with

```

  @content_security_policy (case Mix.env do
    :prod  -> "default-src 'self';connect-src wss://#{@host};img-src 'self' blob:;"

    _ -> "default-src 'self' 'unsafe-eval' 'unsafe-inline';" <>
        "connect-src ws://#{@host}:*;" <>
        "img-src 'self' blob: data:;"
        "font-src data:;"
  end)
```

Now we're dashboarding:

![Screenshot of a working live dashboard](/assets/good_dashboard.png)

This gets us working with a reasonable and working Content Security Policy. In a larger app you may be loading resources from a CDN or other places and will need to keep the policy up to date.


## Useful links

* [Offical documentation](https://content-security-policy.com)
* [MDN documentation](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)
* [An excellent post / Stack Overflow Answer](https://stackoverflow.com/questions/30280370/how-does-content-security-policy-csp-work#30280371)

---- 

[^1]: Another option would be to ignore the advice from Sobelow, and not have such a policy at all. I aver that it is best to not ignore advice from security experts. A Content Security Policy may be a pain to set up and maintain but working through these issues helps us be able to put in place "Defence in Depth" against naughty script kiddies. Think about how the British Airways Magecart hack would have gone if browsers were refusing [AJAX requests to baways.com](https://www.theregister.com/2018/09/11/british_airways_website_scripts/)

[^2]: There's a good chance I will want a protected version of the Dashboard in production; I'll look into the `unsafe-inline`, which does not seem like a great production setting and report back at some point. I expect the clue is in the phrase "its hash, its nonce, or 'unsafe-inline' appears in neither"