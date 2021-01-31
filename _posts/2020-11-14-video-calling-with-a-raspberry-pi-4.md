---
layout: post
title: Video calling with a Raspberry Pi 4
date: 2020-11-14 13:58:13 +0000
author: Paul Wilson
categories: pi
---

[I promised](/2020/11/12/several-months-update.html) to write a bit more about setting up a Raspberry Pi for video calls over Digital Christmas (and more). This is less of a "how to" guide and more of a "how I set it up". There may be better ways.

## Kit

### Raspberry Pi 4

At Cultivate we used a Mac Mini attached to a TV for video calling. I do not want to go to that expense but wanted a similar experience.

I had [Pi Hut](https://thepihut.com) vouchers which were a leaving present from the Edinburgh Deliveroo team. I opted for [8 GB Pi 4](https://thepihut.com/products/raspberry-pi-4-model-b?variant=31994565689406) of memory, which I suspect is overkill. (I also bought other things for other projects, because I can't help myself.)

### 128GB SD card with Ubuntu 64

128 GB is more than is needed but is still [relatively cheap](https://www.amazon.co.uk/gp/product/B073JYC4XM?th=1). I already has a [USB  C](https://www.amazon.co.uk/gp/product/B06XTQVSLL) card reader/writer for burning the OS image. There is no reason, other than curiosity, that I went for Ubuntu rather than [Raspbian](http://www.raspbian.org) which I expect works just as well - if not better.

I downloaded Ubuntu 20.10 desktop, 64 bit for Pi 4, from [here](https://ubuntu.com/download/raspberry-pi). The `xz` file is uncompressable in OS X by double-clicking in the finder.

It's a while since I burnt a [non-nerves](https://ubuntu.com/download/raspberry-pi) image, but found instructions  like [these](https://osxdaily.com/2012/03/13/burn-an-iso-image-from-the-command-line/) - except burn to the disk not the partition. Basically (on OS X)

```bash
diskutil list
```
These showed me the disk was `disk2` and with a partition `disk2s1`.

```bash
diskutil  umount /dev/disk2s1
```

That unmounted the _partition_. The following writes the image.

```bash
sudo dd if=ubuntu-20.10-preinstalled-desktop-arm64+raspi.img of=/dev/disk2 bs=1m
```

That took around 13 minutes, without any feedback.

(Note that the `of` option is the disk not the partition. If you write to the partition, the Pi will not boot.)


Alternative, and probably better, instructions are [here](https://ubuntu.com/tutorials/how-to-install-ubuntu-desktop-on-raspberry-pi-4#2-prepare-the-sd-card)


### HDMI cable and HDMI to micro HDMI adapter for connecting to the TV

I am not sure why we have so many HDMI cables in various drawers, but we do. The Pi 4 has a micro-hdmi port (unlike my Pi Zeroes  which have the larger mini-hdmi - go figure) and I originally got [this adapter](https://www.amazon.co.uk/gp/product/B008MLFJKK) which worked fine but broke when I was arranging the cables, because of the leverage from the stiff cable. I replaced it with this [more flexible adapter](https://www.amazon.co.uk/gp/product/B00B2HORKE).

The Ubuntu desktop spilled over the edge of the TV screen. I changed the resolution in settings to 1680 x 1050 (16:10). 

### (Optional) HDMI switch

Our TV has limited HDMI ports, so getting [this](https://www.amazon.co.uk/gp/product/B07KSYS2L4) is handy. Bear in mind that it needs 5v power though.

### Power and USB-C cable

Pretty much everyone has lots of USB power adapters lying round; I used a powered USB hub that I already had, to provide power to both the Pi and the HDMI switch. The Pi 4 takes power through a USB-C port so I got a [USB-A to USB-C cable](https://www.amazon.co.uk/gp/product/B01GGKYKQM/).

### USB Camera

I got [this one](https://www.amazon.co.uk/gp/product/B086QTK3NL) which works and is manually focusable. Unfortunately the microphone is not good enough for talking when not close to the camera. I plugged the camera into the [USB-3 port](https://www.raspberrypi.org/products/raspberry-pi-4-model-b/specifications/?resellerType=home), because I read somewhere that was better for webcams; I haven't verified this though.

### Microphone

Combined speaker and microphones, like [this that we had at Cultivate](https://www.jabra.com/Business/speakerphones/jabra-speak-series/jabra-speak-510), are excellent for business conference calls and eliminating the echo problem, but I decided they were too expensive for this project. This £20 [wired USB mic](https://www.amazon.co.uk/gp/product/B07SR4K2R9) works great and is only about 8cm in diameter.

### Keyboard with "trackpad"

You would not want to code or write a lot with [this £10 keyboard](https://www.amazon.co.uk/gp/product/B01HDR58VI/) but it excellent for this job. It is small, wireless, and incorporates a track pad. I did think the USB receiver was missing but it was stored in a small compartment on the underside of the keyboard. 

### Heatsink case

When testing video I discovered the Pi CPU gets very hot. A temperature warning gets displayed, [indicating that the cores and GPU are being throttled](https://www.theregister.com/2019/07/22/raspberry_pi_4_too_hot_to_handle/). This [heatsink case](https://shop.pimoroni.com/products/aluminium-heatsink-case-for-raspberry-pi-4?variant=30975055691859) works very well, with the CPU not getting much above 55℃ during calls, as opposed to around 84℃ without.

You can monitor the temperature by running `sensors` from the terminal.  The following, updates every 2 seonds.

```bash
watch -n 2 sensors
```

An alternative to the heatsink case is [a fan](https://shop.pimoroni.com/products/fan-shim) or even [fan case](https://thepihut.com/products/raspberry-pi-4-case-with-cooling-fan) but I find the passive cooling with the heatsink case sufficient.

## Video calling

On the Ubuntu, at least, I had to change the sound output settings to the first "Multichannel Output - Built-in Audio" option to use the TV (over HDMI) as the audio output. It is also worth making sure your USB microphone is selected as the input device.

### Browser

While Zoom and Skype both have Linux builds available they do not have _Arm_ linux builds - so the only options are browser based. I downloaded Chromium anticipating it working better, but I found it did not play well with the the audio output to the TV. The sound went all dalek-like, even that from the settings output test, during a call.

Firefox (on my setup) was the best browser to use. I have tested Jitsi, Zoom, and Google Hangouts. My experience of video calling services, though, is that they can all be inconsistent at times so 

### Jitsi

Jitsi is an opens source project and provides [a free service](https://meet.jit.si) for setting up [WebRTC](https://en.wikipedia.org/wiki/WebRTC) calls. Sadly I have found it a bit glitchy with my setup, losing video and audio at times, but a other times it is fine. There is a tendency for echo feedback to occur so you may need to be active with the mute button.

I believe the free service uses peer-to-peer WebRTC which, in my experience, tends to downgrade with multiple callers. Your mileage may vary.

### Zoom

Since Covid-19 Zoom has become the generic term for video calling. As there is no Arm build available you need to choose the "use Zoom from the Browser option".

On all occasions that I have tried this the video is noticeably laggy, sometimes taking 10 or 20 seconds to catch up. I will not  using Zoom with this setup.

### Google hangouts

Overall this gives the best results. Video quality is quite good and I have not seen much of a lag at all. Echoes are minimal too.

I created a Google account specifically for the Raspberry Pi to use.


## Some other software I set up

We have a (not really used) family Slack account. I set up [Slack Term](https://github.com/erroneousboat/slack-term) to get things like video call urls over to the Pi without too much retyping.

Setting up ssh-server, with authorised keys for your laptop, and Samba for file sharing is also useful.

Lovspotify [https://github.com/spocon/lovspotify](https://github.com/spocon/lovspotify) is an easy to setup [Spotify Connect](https://www.spotify.com/connect/) client for when you want to play Spotifiy on your TV.

## Summary

A Raspberry Pi 4, attached to a TV, is a reasonable solution for family video calling at a fairly cheap price. You will need more than just the Pi - factor in microphones, camera, cabling, power supply, cooling etc...

At the moment Google Hangouts seems to provide the best experience.

# Updates

* **2020-01-31** corrected the disk burning instructions