---
layout: post
title: I have released some Elixir Nerves Libraries
date: 2023-01-23 14:28:40 +0000
author: Paul Wilson
categories: nerves elixir
---

I recently got back to a slow burn project to make a security system for my home-office, with [Elixir Nerves](https://nerves-project.org). Being one of my projects, it was an Umbrella Project. The last time I posted it was to [(relucanctly) leave Umbrellas behind]({% post_url 2022-09-14-leaving-the-umbrella-behind %}), so I did think about flattening the project.  Instead I realised that most of apps were generally reusable, at least by me[^1], so instead I have extracted them into their own [hexicles](https://mastodon.social/@paulwilson/109721602345750131). 

## Configuration: embracing the anti-pattern 

I tend to not configure too much within project code as it's generally as easy to to change a module attribute as it is to change a value in a config file. I did feel like I had to make things a bit more configurable; someone else probably doesn't want to be stuck with my random GPIO pin choices, for instance.

I went with the laziest choice of using application configuration in all the extractions so far, as in the library customisation method that is [specifically called out as an antipattern in the Elixir Library Guidelines](https://hexdocs.pm/elixir/1.14.3/library-guidelines.html#avoid-application-configuration). In general, I agree with that guideline[^2]. I've ignored it here as none of the extracted libraries could be used with multiple configurations, and it is the simplest to write and for clients to use. 

## Logging

In general I am not too keen on libraries that log. I figure that it is better to find some way to communicate the information back to the client and let it decide what to do. Nerves stuff logs a lot though, so I figure why buck that trend and make things more complicated? So I have kept logging in.

## Are Umbrella Projects still bad?

I don't know. The [previous objections]({% post_url 2022-09-14-leaving-the-umbrella-behind %}) still stand, but there is something to be said for easily writing code for a subsytem _in-situ_ then extracting it out into its own library later. I should force myself to write a bit more about this.

## THE HEXICLES!!!

Here they are:

### Vintage Heart

* [Github](https://github.com/paulanthonywilson/vintage_heart/)
* [Hexdocs](https://hexdocs.pm/vintage_heart/readme.html)
* **Mix Install** `{:vintage_heart, "~> 0.1.1"}`

I often seem to be plagued by intermittent loss of connectivity over WiFi. Everything will work for days, even weeks, and then the device will keep dropping offline. Intermittent things are really difficult to debug[^3], compounded by it being difficult connect to an offline device.

Vintage Heart keeps an eye things by using [VintageNet connectivity checking](https://hexdocs.pm/vintage_net/readme.html#internet-connectivity-checks) and takes action if offline for a period. By default it will

* Kick VintageNet after 4 minutes of being offline. By kick, I mean kill the `VintageNet.RouteManager` process, which normally does the trick[^4].
* Causes a reboot after 14 minutes, during which time there would have been 3 failed kicks.

### Connectivity LED status

* [Github](https://github.com/paulanthonywilson/connectivity_led_status/)
* [Hexdocs](https://hexdocs.pm/connectivity_led_status/readme.html)
* **Mix install**: `{:connectivity_led_status, "~> 0.1.2"}`

On the connectivity theme, uses an onboard LED to indicate connectivity status. 

* Flashes rapidly if no WiFi address is allocated
* Flashes a heartbeat (2 rapid flashes then a pause) if a IP address is established but VintageNet is not reporting Internet connectivity
* Flashes in a measured way when the VingateNetWizard is up
* Does not flash when a WiFi address (other than the VintageNetWizard) is allocated and Network connectivity is established

I find it useful to have a visual clue about how connected a device is.

### Vintage Net Wizard Launcher

* [Github](https://github.com/paulanthonywilson/vintage_net_wizard_launcher/)
* [Hexdocs](https://hexdocs.pm/vintage_net_wizard_launcher/readme.html)
* **Mix install**: `{:vintage_net_wizard_launcher, "~> 0.1.0"}`

The Vintage Net Wizard is a super-useful little [hexicle](https://hexdocs.pm/vintage_net_wizard/readme.html) that configures the WiFi to AP mode and sets up a little webserver. Someone can then connect to the hotspot and configure the actual WiFi details.

This launches the wizard, so you don't have to. By default:

* It launches the wizard on startup, if the WiFi is unconfigured
* It launches the wizard if GPIO pin 21 is detected as being high (ie under voltage) for 3 seconds. For instance if you have connected 21 to 3V via a button, and pressed it for 3 seconds.

### DS18B20

* [Github](https://github.com/paulanthonywilson/ds18b20)
* **Mix install**: `{:ds18b20, git: "git@github.com:paulanthonywilson/ds18b20.git}`

DS18b20 is a digital thermometer that uses the weird [1-Wire](https://en.wikipedia.org/wiki/1-Wire) system. This library supports reading the temperature as long as you've gone through the [shenannigans to enable 1-Wire](http://www.carstenblock.org/post/project-excelsius/), and this is the only 1-Wire device used. For convenience [you can subscribe](https://github.com/paulanthonywilson/ds18b20/blob/main/lib/ds18b20/temperature_server.ex#L36-L41) to get a reading every minute.

I haven't published it to Hex, as there is now [a project there ahead of me](https://hex.pm/packages/ds18b20_1w). I haven't tried it but it does seem better in that it supports multiple sensors.

### Simplest Pub Sub

* [Github](https://github.com/paulanthonywilson/simplest_pub_sub/)
* [HexDocs](https://hexdocs.pm/simplest_pub_sub/readme.html)
* **Mix install**: `{:simplest_pub_sub, "~> 0.1.0"}`

Simple wrapper of [Registry](https://hexdocs.pm/elixir/Registry.html) for using Pub Sub. It's really only there to save me writing the same 10 lines of code over and over again. I'm not writing in [Go](https://go.dev).

It also means that my extracted hexicles can share a pub-sub registry.

### Next up, movement detection for determining whether a room is occupied

An [HC-SR 501 infra-red sensor](https://duckduckgo.com/?q=HC-SR501) is a cheap device for detecting movement. Next I'll extract out a hexicle to  broadcast to subscribers

* when movement is detected
* when movement is no longer detected
* when movement has not been detected in a while, so that we can determine that a (small, like my office) room is unoccupied
* when an unoccupied room becomes occupied

Watch this space.






---

[^1]: Don't tell anybody but I have been known to entirely copy an Umbrella app from one Nerves  project and paste it into another. Hey! They're my projects; stop judging.
[^2]: Actually I'm not super keen on many of the other bits in the library guidelines. To me, it is often too prescriptive and is sprinkled with general programming (as opposed to library) advice. I should write something about it sometime.
[^3]: It may be an issue with my home network. I even occasionally get loss of connectivity on my phone when wandering between rooms; I suspect it's to do with switching between access points but I ain't no network engineer.
[^4]: I worked this out while connected to a Pi Zero W over USB, while the Pi was having WiFi issues. 