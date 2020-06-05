---
layout: post
title: EC2 instance provisioning with cloud-init
date: 2020-06-05 15:25:02 +0100
author: Paul Wilson
categories: log aws terraform
---

The last thing I [wrote about yesterday]({% post_url 2020-06-04-adding-ssl-to-our-little-service %}) was making our little web service a bit more secure with SSL, and we are about ready to start deploying an Elixir app to AWS. Before that, though, I wanted to satisfy my curiosity by provisioning the instance using [`cloud-init`](https://cloud-init.io) rather than relying on, the somewhat frowned-upon, [`remote-exec`](https://www.terraform.io/docs/provisioners/remote-exec.html).

In this example, `remote-exec` is basically used to install [`nginx`](https://www.nginx.com) using [`apt-get`]( https://help.ubuntu.com/community/AptGet/Howto) via `ssh`. Using `cloud-config` (part of `cloud-init`) we can get the server to do this itself on boot. [This example file](https://cloudinit.readthedocs.io/en/latest/topics/examples.html) is pretty useful in figuring things out.

The first thing was to create a [yaml](https://yaml.org) file, which I called `cloud_config.yaml` and put in the same directory as the Terraform. The contents were

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
    - nginx

runcmd:
    - service nginx start
```

The comment `#cloud-config` is treated as a directive and is essential.

`package-update` runs `apt-get update` to make sure the package list is up to date. `package_upgrade` runs `apt-get upgrade` to make sure everythig is up to date. Next under `packages` we make sure that `nginx` is installed and the `runcmd` starts `nginx`.

We add this to our instance `resource "aws_instance" "web"` with the attribute

```terraform
  user_data  =  file("cloud_config.yaml")
```

There's also the option to [use Terraform templates](https://www.terraform.io/docs/providers/template/d/cloudinit_config.html), but whatevs.

And that's it, and we can run `terraform apply`. Except it didn't work when I did that 🙀: browsing to the ELB's address gave a blank page rather than the Nginx welcome page. Clicking around the console it showed that the ELB considered the instance "Out of service". It had failed the health checks.

Provisioning `remote-exec` means that the Terraform waits for that to complete before setting up the ELB. With `cloud-init` the ELB is set up before `nginx` is up, so the health check can fail. The default health check configuration is to check every 30 seconds, to consider unhealthy after 2 failed checks and to then need 10 checks to be considered healthy. My mental arithmetic makes that at least 5 minutes until a failed instance will be considered healthy again. I changed the timings with Terraform configuration of `resource "aws_elb" "web" `

```terraform
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 5
  }
```
I also changed the protocol (with the `target` attribute) to `http` from `tcp`. This is almost certainly less optimal, but it was good for debugging: by ssh'ing on to the box I could then `tail -f /var/log/nginx/access.log` to see the heartbeats. 

No hearbeats. Instance still out-of-service. No dice.

It turns out that for no reason I can fathom the ELB lost the ability to route to the subnet of the instance, when the instance was configured in this way. There are two solutions (that I found from trial, error, and hints on Stack Overflow) to this:

* Make the ELB and the instance share the _same_ subnet
* Make an explicit _local_ egress rule from the ELB to the VPC in the ELB's security group.

I settled on the latter. In `resource "aws_security_group" "elb"`:

```terraform
  egress {
    from_port = 80
    to_port =  80
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
```

The Terraform for all of this is now [here](https://github.com/paulanthonywilson/examples-from-terraform-provider-aws/blob/4b733e2b5b5c0386b0a5f52170b9afe7d82bcb4c/two-tier/main.tf).