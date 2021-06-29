---
layout: post
title: What happens when a linked process dies
date: 2021-06-08 11:27:41 +0100
author: Paul Wilson
categories: elixir otp
---

{% include_relative livebook/linked-process-death.livemd %}

{% include_relative shared/otp-process-death-series.md %}

## Updates

* **2020-06-28** Added check to code to show that a process trapping exits does not die when a linked process dies with `:normal`, just like when not trapping exits.

* **2021-06-29**: included the section linking to posts in this series.

* **2021-06-29**: added a note that this post does not look at linked processes with a parent/child relationship.
