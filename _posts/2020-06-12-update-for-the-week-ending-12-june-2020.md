---
layout: post
title: Update for the week ending 12 June 2020
date: 2020-06-12 10:40:35 +0100
author: Paul Wilson
categories: log aws terraform
---

It's not been a great week for logging, partially because I have felt distracted, unsure of which direction to go in, and have not really achieved _the thing_, whatever _the thing_ is. I guess I am also unclear what this is really for, because writing up as I go is not organised enough for anyone else to follow. Maybe I should write recap, tutorial-style posts, after getting a useful thing written and deployed.

## Pet burial

The week started off a little sad. Padfoot, one of our two remaining guinea pigs, died overnight on Monday, shortly after getting a diagnosis of bone cancer. We buried her in the back garden, which involved hours, on Tuesday, of me making a grave in the wooded part. Digging through tree roots and into clay is hard.

<img src="/assets/pigs.jpg" style="margin: auto; display: block">

Left to right, Ned who died last month, Padfoot, and Prongs. Prongs is lonely now so we are thinking of getting her a new companion.

## More AWS and Terraform, now with deploys


Just a brief outline here. I will try and write a more coherent tutorial when I have something more coherent to write. This week I was working on approaches to deploying an actual Elixir application. I have been working with [this freshly generated one](https://github.com/paulanthonywilson/correct-horse-elixir/commit/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf). (I've linked to a particular commit).

### Elixir release

This is the first time I have used built-in releases, rather than [distillery](https://github.com/bitwalker/distillery). Unsurprisingly it's not too different. The challenge is, of course, compiling for the target and including the appropriate runtime, when I still develop on OS X and am deploying to Ubuntu. There are various options including:-

* **Compiling on the target box**. This just seems wrong. One of the nice things about a release is that (by default) it includes the Erlang runtime so we only need to set up a vanilla operating system and we're ready to go. This is messier and increases the replacing VMs, clustering (if we decide to go down that root), and importantly _feels icky_.
* **Having a dedicated VM for releases**. At Cultivate I had set up a box for just this, on Digital Ocean, and used [eDeliver](https://github.com/edeliver/edeliver). It was a pain to maintain, especially for multiple projects on slightly varying versions of Elixir/Erlang, and meant paying for a box just to make releases. A full scaleable and robust solution, as described at last year's ElixirConf [Elixir in the Jungle](https://github.com/piisalie/aws_training_elixirconf_2019) tutorial, built and released from the Bastion. I am not planning on investing in that robust of a solution right now.
* **Local docker**. Having got fed up of maintaining the Cultivate _edeliver_ release, I switched to making releases locally but through an appropriate Docker container. That is using Docker to create the release, but **not** deploying with Docker. This is a nice flexible approach and I opted to go down this route again. Of course, it got fiddly.

The Dockerfile for setting up the build environment is [here](https://github.com/paulanthonywilson/correct-horse-elixir/blob/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf/deploy/docker_build/Dockerfile). Things to note:

* I'm releasing to Ubuntu so it's an Ubuntu based Docker.
* The default Erlang solutions Linux package was a little old, so I opted for using ASDF to neatly specify Erlang and Elixir versions. Only as I write this do I stumble upon [up to date versions](https://www.erlang-solutions.com/resources/download.html). 
* Node is not installed using ASDF. I have previously found the  [GPG signature check](https://github.com/asdf-vm/asdf-nodejs) to be a major headache to maintain in automatically provisioned setups. 

The shell script for building _within_ the Docker container is [here](https://github.com/paulanthonywilson/correct-horse-elixir/blob/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf/deploy/docker_build/build). Note:

* I'm using local _git_ repository for the build rather than downloading from the remote repo. It's a bit more a of a scrappy approach but sidesteps lots of configuration setup.
* In the past I have built within a shared volume, directly to my working copy. This can lead to awkward clashes if I have, for whatever reason, compiled to production within OS X. It now _does_ lead to an awkward clash on the npm install, between OS X and Linux components. Instead I copy over the `.git` directory to a build space, and checkout a fresh version of whatever branch I'm currently on.
* The [secret key generation](https://github.com/paulanthonywilson/correct-horse-elixir/blob/3540cc27dad6ecb4a570ca221bc39d18697e11f0/deploy/docker_build/build#L34) is kind-of awkward.
* I have a note, to do the same kind of thing for the LiveView salt.

It's all tied together with [this](https://github.com/paulanthonywilson/correct-horse-elixir/blob/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf/bin/make-release) script to create the image, and release from it.


### AWS infrastructure 

The infrastructure setup is based on the examples [from last week]({% post_url 2020-06-05-ec2-instance-provisioning-with-cloud-init %}). The main Terraform file is [here](https://github.com/paulanthonywilson/correct-horse-elixir/blob/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf/deploy/terraform/main.tf). One major difference is that the [Elastic/Classic) Load Balancer](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/load-balancer-types.html#clb) has been replaced with the [Application Load Balancer](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/load-balancer-types.html#alb).

Turns out the the simpler classic version [does not support](https://jayendrapatil.com/aws-classic-load-balancer-vs-application-load-balancer/#WebSockets) Websockets, which is not terribly well documented. This would be a problem for [LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html).

Application Load Balancers require that they are attached to at least two subnets in different [availability zones](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html). This makes sense in terms of maximising resilience in case of outage, which is not a thing that's bothering me right now. I ended up creating a [spare subnet](https://github.com/paulanthonywilson/correct-horse-elixir/blob/7b43ec8f9d05ec2df5c9f004b161bfc6c39689bf/deploy/terraform/main.tf#L32), with nothing else attached, which is a bit of a hint that load balancing is over-egging things right now.

### DNS

I also added another cheeky wee [Terraform file](https://github.com/paulanthonywilson/correct-horse-elixir/blob/master/deploy/terraform/dnsimple.tf) to automate setting up the DNS in [DNSimple](https://dnsimple.com/) every time I recreated the infrastructure.

### Deploying the release

I had an initial plan to (for now) upload the release using the Terraform [file provisioner](https://www.terraform.io/docs/provisioners/file.html) and maybe untar and start it with a [remote exec](https://www.terraform.io/docs/provisioners/remote-exec.html). The 18mb gzipped tar file times out on upload, quashing that option.

For now I am doing it with a separate [shell script](https://github.com/paulanthonywilson/correct-horse-elixir/blob/master/bin/deploy-release). It works. (If you're wondering about the `service start` stuff, the application is made a `systemd` service [here](https://github.com/paulanthonywilson/correct-horse-elixir/blob/master/deploy/terraform/cloud_config.yaml))

I would like to try using [Packer](https://www.packer.io) to create a custom API that contains the release.

### Thoughts on the load balancing

Load balancers are a chunky bit of kit, and so far I am only deploying a single instance. Running the figures, once I've exhausted by [free tier](https://aws.amazon.com/free/?all-free-tier.sort-by=item.additionalFields.SortRank&all-free-tier.sort-order=asc) an active load balancer will cost $0.023 per hour or about $16.80 per month compared to about $8.50 for an unreserved `t2.micro` instance. With a single instance there's no load to balance.

For now it's overkill for a hobby project. For something with remotely production like needs, it would probably be worth load balancing across [availability zones](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html) and probably [autoscaling](https://docs.aws.amazon.com/autoscaling/ec2/userguide/AutoScalingGroup.html).

It is a pretty convenient way to deal with Amazon issued SSL certificates though; much easier than approaches using [Let's Encrypt](https://letsencrypt.org) (awesome as it is). For that reason, and that I've still free-tier allowance, I'm willing to swallow any cost for now, but it would be good to look into a simpler single instance setup.

