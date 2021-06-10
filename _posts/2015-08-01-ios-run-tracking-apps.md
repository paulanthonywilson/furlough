---
layout: post
title: iOS run tracking apps, signal and noise
---

I've been tracking runs with [Runkeeper](http://runkeeper.com) on iPhones for about 7 years. Tracking apps are dependent on the hardware for the location information, which is sometimes more accurate than others. I normally train on the North Edinburgh shared cycle routes, along former railway lines; in parts the path sunk to about 5m, frequently going under road-bridges, neither of which is great for GPS accuracy. Also, in my experience, the phone's GPS performance seems to degrade after about 18 months.

Poor GPS leads to apparent zig-zagged routes, artificially inflating the distance and pace of the run.

![Poor runkeeper track](/images/run_tracking/runkeeper-bad.png)

I've been finding this increasingly irritating. If the tracked run doesn't accurately reflect the actual run, then what's the point of tracking? And while [Runkeeper](http://runkeeper.com) can only record what it's told by the hardware, I figure there must be an algorithmic solution to smoothing out zigzagging GPS points.

A few weeks ago [I tweeted about the issue](https://twitter.com/paulanthonywils/status/623393466467401728) and received some suggestions for alternative apps. [Christoph](https://twitter.com/ChristophGockel/status/623395497307435009) likes [Runtastic](https://www.runtastic.com); [Florian Gilcher](https://twitter.com/Argorak/status/623540171171086337) is pretty happy with [trails.io](https://trails.io/en/); [Matthew Lang](https://twitter.com/matthewlang/status/623397800546582528), [Matt Farrugia](https://twitter.com/mattfarrugia/status/623398314902482945), and [Gar Morley](https://twitter.com/garmorley/status/623399139548770304) suggested [Strava](https://www.strava.com); [Russ Freeman](https://twitter.com/russnettle/status/623468776206544896) uses the [Nike+](https://secure-nikeplus.nike.com/plus/) app, without issues. 

For the past few weeks I've been simultaneously recordings runs with multiple apps, to see if any do a better job of dealing with poor GPS readings than Runkeeper, and here's a quick overview (tl;dr  [Nike+](https://secure-nikeplus.nike.com/plus/) wins).

## Runkeeper

You can edit your [Runkeeper](http://runkeeper.com/home) running map, after your run to make it a bit more sensible. Sometimes I do this, but it's very tedious. My latest approach is to just delete bad points and rely on "snap to roads" to correct the routes.

### Other things I like

* **Audio cues** I like getting updates on distance, pace, and time through the headphones at set intervals. This does transform into annoying when a set of poor GPS readings makes the cues inaccurate.
* **Programmable training** Being able to set up interval training with audible cues can be useful for speed-training runs
* **Map with track** One of the in-run options is to be able to see a map of the location, with a track showing the run so far. I've found this great for recovering from getting lost, when running in foreign cities.

### Other annoyances

* **Unethical review policy** Sometimes it asks for feedback at the end of a run. If you give it a top score, it will send you to the App Store to put in your great review. Poor scores take you to an email to Runkeeper support.

### Verdict

If I was happy with Runkeeper, I wouldn't have been doing this.

## Strava

[Strava](http://strava.com) tracks (top) are pretty much the same as bad as Runkeeper tracks (bottom).

![Strava track](/images/run_tracking/strava.png)
![Runkeeper track](/images/run_tracking/runkeeper2.png)

### Verdict

I use Strava to track my bicycle commutes, mainly so I have a record of speed in case I have another incident. Somehow I'm not keen on mixing up my fitness (running) data with my just-getting-to-work-and-back data.  Strava doesn't seem to have Audio cues, either.

Without any improvement in dealing with poor GPS data, there's no reason to choose Strava over Runkeeper.

### Trails.io

Again, [Trails.io](http://trails.io) tracks(top) tracks don't differ from Runkeeper(bottom).

![Trails.io track](/images/run_tracking/trailsio.jpg)
![Runkeeper track](/images/run_tracking/runkeeper3.png)

To be fair there are options to configure the "required accuracy" of GPS points, claiming that points below that accuracy will be discarded, but I just accepted the suggested defaults for running. (Horizontal accuracy level is provided by iOS in [Core Location](https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CLLocation_Class/index.html#//apple_ref/occ/instp/CLLocation/horizontalAccuracy) along with position information.)

### Verdict

Trails.io seems aimed more at walkers than runners. It looks like it has some good battery saving features, such as automatically locking the screen and enabling the sampling frequency of GPS points to be configured. It does not provide audio cues.

I should perhaps have played more with the _required accuracy_ setting to have given it a fairer go at beating Runkeeper at dealing with poor GPS. However the lack of audio cues rules it out as a tracking application for me, for now.


## Runtastic

[Runtastic](https://www.runtastic.com/) (top) deals no better than Runkeeper (bottom ) with poor GPS readings.

![Runtastic track](/images/run_tracking/runtastic.png)
![Runkeeper track](/images/run_tracking/runkeeper4.png)

### Verdict

I used the free version which provides Audio cues for the first 2km. If I were to switch, then upgrading to the pro version seems fair enough.

However without better algorithms to deal with rogue GPS readings, I have no reason to switch.

## Nike Plus

Unlike the other apps, [Nike+](http://nikeplus.com) (top) gives different results to Runkeeper (bottom).

![Nike+ track](/images/run_tracking/nike1.png)
![Runkeeper track](/images/run_tracking/runkeeper4.png)

My guess is that it does this by simply discarding poor GPS readings, and assuming a straight line between the good ones. The poor GPS areas can bee seen as a dotted line when looking at the activity in the app (but not in the web app)

![Nike+ activity in app](/images/run_tracking/nike2.jpg)

## Verdict

Nike+ gives audio cues, and an intuitive interface including a well thought out in-run screen. It is quick to detect pauses (eg for crossing the road).

Of course my favourite feature of Nike+ is that it detects, and deals reasonably, with poor GPS data. Straight lines between the good readings is a good-enough approach.

## Conclusion

I'll be switching to Nike+.


