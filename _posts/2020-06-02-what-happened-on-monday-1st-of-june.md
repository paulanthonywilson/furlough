---
layout: post
title: What I did on Monday 1st of June
date: 2020-06-02 09:20:10 +0100
author: Paul Wilson
categories: log 
---

I took the weekend off.

## Deploying Elixir

Over the weekend I did fall to contemplating the next steps, which ought to be a project - probably Elixir based. In the first instance I would like to deploy something that uses [LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html). I could press ahead and get something running locally, but in my experience it is quite disheartening to feel like the work is done but then spend ages getting a decent deployment together.

So, on Monday morning I reviewed some options.

### Heroku

[Heroku](https://www.heroku.com) is nice and easy, but unsatisfying. In many ways it [fails to let Elixir shine](https://hexdocs.pm/phoenix/1.5.3/heroku.html#limitations). My personal experience of using Heroku for 38 Degrees' sentiment and live polling app, live the 2014 Brexit referendum, put me off Heroku as an Elixir deployment target: in load testing it started to fail at around 700 websocket connections and we had to throw many [dynos](https://www.heroku.com/dynos) at it during the debates.

It also gets pretty expensive after you've a few projects up (or need to scale) these days.

### Digital Ocean and Ansible

[Cultivate](http://cultivatehq.com)'s collection of apps and sites was deployed on [Digital Ocean](https://www.digitalocean.com). I do like the simplicity of Digital Ocean: a few clicks and there you have a [droplet](https://www.digitalocean.com/products/droplets/) running exactly what you think is running.

I had concocted an Ansible repository, to provision Cultivate's estate. Munged together with some Bash, it also managed setting up and renewing SSL certificates via [Let's Encrypt](https://letsencrypt.org) and [DNSimple](https://dnsimple.com)'s API.

Honestly it was not pretty, but it was lovely to use. The ability to take down a droplet for an upgrade (or because of a mistake) and have it replaced in minutes was sweet.

As an aside, one of the reasons for its ugliness was my distrust of using [Ansible Galaxy](https://galaxy.ansible.com). I do not feel great about using scripts, hidden away from the main repository, that poke around with infrastructure. Instead I would copy the relevant parts out and paste them into the Cultivate Ansible repository.

I decided against reproducing this approach for several reasons:

* I would end up copying and reusing some of the messy parts of Cultivate's infrastructure repository.
* I would almost certainly be stuck in tedious work updating the deprecated parts.
* It still needs manual creation and management of droplets.
* Ansible uses [YAML](https://yaml.org), and programming in YAML is not fun.
* I would not learn much new.
* Ansible is a name that I associate with [Orson Scott Card](https://en.wikipedia.org/wiki/Orson_Scott_Card)'s fiction, which I find politically problematic. 


### Digital Ocean and Terraform

I'd mean meaning to get to grips with [Terraform](https://www.terraform.io) for some time, so I started to look into it with Digital Ocean. [This tutorial](https://www.digitalocean.com/community/tutorials/how-to-use-terraform-with-digitalocean) looked promising, but doesn't provide much more than a taster.

[This tutorial](https://learn.hashicorp.com/terraform/getting-started/intro) on the main Terraform site is much richer but uses [AWS](https://aws.amazon.com) which leads to ... 

### AWS and Terraform

The reason I am attracted to Digital Ocean, is that AWS makes me feel stupid. I get overwhelmed by the proliferation of options, the truly awful web interface, and the cognitive overload of its poor user experience with multiple frustrations. For instance, unless it is just to annoy me, I don't get why it needs to refer to the full names of regions in some places and the short names in others; I have to hold in my head that North Virginia is "us-east-1" and Ireland is "eu-west-1".

On the other hand, professionally, I would benefit with being more comfortable with AWS and that's the way the tutorials point.

## Learning Terraform with AWS

So, off I went following [the AWS with Terraform](https://learn.hashicorp.com/terraform/getting-started/intro) tutorial. First step was to create a new AWS account; I don't control Cultivate any more and the last time I logged on to its AWS account I failed to get past the verification phoning the company's now disconnected landline. Also, yay for 1 year free trial (limitations apply).

Registration was fairly straightforward then I was confronted with using the root account (bad practice) and creating a new [IAM](https://aws.amazon.com/iam/) (messed this up before now). I created the IAM,and it was not too bad. I went for giving it full admin access, on the principle that its tutorials for now and I can always tighten things up when it gets a bit more serious.

Tip: there's no point in making the IAM username an email address.

The tutorial itself was clear and worthwhile, covering aspects of which I was unclear, such as how the variables work. One optional exercise did not work: [provisioning with remote exec](https://learn.hashicorp.com/terraform/getting-started/provision#defining-a-provisioner) timed out on attempting to connect with ssh. This turned out to be because the [default security group](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html) only allows incoming connections from within the same security group. Changing the rules on the default allowed the provisioning to go ahead, though this does not seem like good practice.

I suspect that there is a public Github repository for the tutorial but I could not find it to add an issue.

## Next steps

### Setting up an appropriate security group

It would be good to get the provisioning exercise working in a safer way, probably by setting up an appropriate security group within the Terraform.

### Figuring out provisioning

By provisioning I mean updating and installing the appropriate packages and software. (I still think I would prefer to _deploy_ the application outwith infrastructure setup.)

Using `remote-exec` to provision with Terraform is frowned upon, as are [all provisioners](https://www.terraform.io/docs/provisioners/index.html). I don't relish the idea of running a separate Ansible, or Chef or Puppet or whatever to provision.

I am planning to look into [cloud-init](https://cloudinit.readthedocs.io/en/latest/) which at first [does not seem to have the clearest documentation](https://cloudinit.readthedocs.io/en/latest/#) but looks promising from the video on [its brochure page](https://cloud-init.io).

[Docker](http://docker.com) is also a possibility, and I think most people reach for that these days. I am wary of pulling on that thread: unmanaged containers will cry out to be managed and the next thing there'll be some unwieldy and expensive Kubernetes cluster to manage. Also would anticipate some tedious working around Docker to take advantage of [Beam](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)) features. 

### Setting up a basic two tier architecture

[This example](https://github.com/terraform-providers/terraform-provider-aws/tree/master/examples/two-tier) seems just what I'm after, hopefully figuring out setting up the  [Elastic Load Balancer](https://aws.amazon.com/elasticloadbalancing/) to hold the SSL certificates. 

Maybe a third tier could be an [RDS PostgreSQL](https://aws.amazon.com/elasticloadbalancing/) instance.

## End of day

After our family's evening walk, I set up this blog and wrote about last week. It would be too meta to write much about the setup here, beyond that is hosted via [Github Pages](https://pages.github.com) as a project site. Its repo is [here](https://github.com/paulanthonywilson/furlough).





