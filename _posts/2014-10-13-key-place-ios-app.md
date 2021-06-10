---
layout: post
title: Key Place iOS App
---

![Key Place Screenshot](/images/keyplace.png)

[![On the app store](/images/appstore.svg)](https://itunes.apple.com/gb/app/key-place/id917796480)

A few year's ago Nationwide Building Society added an extra [partial password](https://en.wikipedia.org/wiki/Partial_Password) to their login. Rather than asking for the full password, they ask for 3 characters. The theory is that key loggers (or people looking over shoulders) would find it harder to get the full credentials.

Remembering a password then counting characters, without first writing it down, was something I found difficult. Eventually I got quite good at logging into Nationwide. Then it became a popular technique, for web logins and also telephone security questions. One partial password I could cope with; several I could not. When one credit card started asking me to count into a 16 character password I started using a Ruby script to help me log in.

i{% gist paulanthonywilson/1239165 %}

That was ok, but still a bit of a pain. I also tended to have terminals hanging around, running _passy_ with my passwords written down. It was also no good for logging into things when I was on my phone or iPad.  When Apple released [Swift](https://developer.apple.com/swift/), I found that I wanted to get back into iOS development. So I wrote a password manager, in Swift, specifically for managing these types of passwords and _easily_ displaying just those characters needed.

It is secure but not that fancy. The passwords are stored on your device only, but you should not have too many of those types of passwords. I do use 1Password for my proper passwords.

It is now available on the [iOS app store](https://itunes.apple.com/gb/app/key-place/id917796480), for iPhone and is currently free. I hope some other people find it useful. If you do, then I _would_ really appreciate some more reviews.

[![On the app store](/images/appstore.svg)](https://itunes.apple.com/gb/app/key-place/id917796480)
