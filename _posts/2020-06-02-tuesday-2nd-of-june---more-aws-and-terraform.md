---
layout: post
title: Tuesday 2nd of June - More AWS and Terraform
date: 2020-06-02 16:44:52 +0100
author: Paul Wilson
categories: log aws terraform
---

I spent most of today writing up yesterday, which is fine. While it does feel like a block on progress, it reinforces the learning and provides notes for me. Now I have this log, then it makes more sense to write up as I go.

Just now, I did get the [provisioning with remote-exec](https://learn.hashicorp.com/terraform/getting-started/provision#defining-a-provisioner) working with security groups. If you recall, [yesterday](/log/2020/06/02/what-happened-on-monday-1st-of-june.html), I went in and messed with the default security groups for a region via the web console to show it was a security group issue.

The 'aws_security_group' documentation is [here](https://www.terraform.io/docs/providers/aws/r/security_group.html). I included the default _all ports, all destinations_ egress as recommended. For the `ingress` I limited it to port 22, for ssh, and 80, to show that nginx is running.

```terraform

  ingress {
    description = "SSH in"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP in"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

A tricky part was figuring out how to apply the security group to the default VPC. I could not figure out how to  `aws_default_vpc` resource from [this documentation](https://www.terraform.io/docs/providers/aws/r/default_vpc.html). Fortunately Stack Overflow [came through in the end](https://stackoverflow.com/questions/60619873/how-to-get-the-default-vpc-id-with-terraform):

```terraform
data "aws_vpc" "default" {
  default = true
} 

resource "aws_security_group" "allow-ssh-in" {
  name="allow-ssh-in"
  description = "allow ssh in"
  vpc_id      =  data.aws_vpc.default.id
```

The we need to apply the appropriate security group to the instance

```terraform
resource "aws_instance" "example" {
  ami           = "ami-083cf3480acb8f8af"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow-ssh-in.id]
```

The whole example is in the _gist_ below.


{% gist e937d422f4d05492aca3a08a4f691d70 remove-exec-provision.tf %}