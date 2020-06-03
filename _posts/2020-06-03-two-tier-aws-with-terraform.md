---
layout: post
title: Two tier AWS with Terraform
date: 2020-06-03 15:29:27 +0100
author: Paul Wilson
categories: log terraform aws
---

After [emailing my MP](https://twitter.com/paulanthonywils/status/1268115099497136128) hoping she will support suspending exports of riot control equipment to the USA, it was time to get on with more learning about AWS and Terraform.

[Previously]({% post_url 2020-06-02-tuesday-2nd-of-june---more-aws-and-terraform %}) I'd figured out configuring a security group to be able to ssh on to an AWS instance. A good next step was to use the [example code](https://github.com/terraform-providers/terraform-provider-aws/tree/master/examples/two-tier) to set up a basic two tier architecture - an EC2 instance fronted with an [Elastic Load Balancer](https://aws.amazon.com/elasticloadbalancing/).

I created a new ssh key with `ssh keygen -t rsa`, this time adding a secret passphrase. It's easier enough to use `ssh-add` with the private key file, to add the passphrase to [`ssh-agent`](https://en.wikipedia.org/wiki/Ssh-agent).

I also chose to create a `terraform.tfvars` file in the example directory to hold the configuration variables.

```terraform
key_name = "terraform-scratch-key"
public_key_path = "~/.ssh/terraform-scratch-key.pub"
aws_region = "eu-west-1"
```

Now `terraform apply` works just great. The output shows the url of the ELB, serving the default `nginx` page. It took a minute or so to come up, so at first it did look like something had gone wrong.

This sets up quite a bit more than happens in the [getting started tutorial](https://learn.hashicorp.com/terraform/getting-started/intro), though it still takes place in quite [a small file](https://github.com/terraform-providers/terraform-provider-aws/blob/master/examples/two-tier/main.tf). Let's dig in a bit.

```terraform
provider "aws" {
  region = "${var.aws_region}"
}
# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}
```
Rather than relying on the default [Virtual Private Cloud](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) (VPC) we are setting up one dedicated to this architecture (not sure how to term it), which makes a lot of sense. I imagine it will avoid clashes with domains, and reduce the blast radius of security or other faults.

It does seem a bit weird and confusing to name this VPC "default", as it is _not_ the default VPC. Maybe this is a convention, meaning the default for the architecture. I haven't seen enough Terraform to be sure.

The `cidr_block` sets up the allowable IPV4s in the VPC. It's probably just me, but I often have trouble remembering the meaning of that format. "/16" means that there are 16 bits in the routing prefix: 16 bits is, of course, 2 bytes so it is the equivalent of a subnet mask of "255.255.0.0".


```terraform
# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}
```

Every VPC needs an [internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html), if it is to communicate with the outside world and (apparently) a fresh routing table too. AWS's motto is surely "more assembly required than you would think".

```terraform
# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}
```

While the VPC has it's own CIDR, we also need at least one  subnet needed. (    The default VPC we used in the tutorial comes [with its own default subnet](https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc.html)). I get the impressions that subnets within a VPC seem to be primarily about providing [defence in depth](https://en.wikipedia.org/wiki/Defense_in_depth_%28computing%29), for instance by separating the public and private components of the system.

```terraform
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

The load balancer will need its own security group, allowing incoming connections only on port 80 (as we don't have ssl setup). I am unclear why the outgoing connections need to be allowed.

```terraform
# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

The EC2 instance also needs its own security group. SSH connections are allowed for anywhere, and will be used later for provisioning. HTTP (port 80) connections are only allowed from withing the VPC. Note that this is the VPC CIDR, not the subnet one. That is something to dig into on a later occasion.

```terraform
resource "aws_elb" "web" {
  name = "terraform-example-elb"

  subnets         = ["${aws_subnet.default.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}
```

The ELB definition is pretty simple, tying it to the _default_ subnet, its security group, and the instance. Default is word that's doing a lot of heavy lifting in this example.

```terraform
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}
```

The key pair will allow `ssh` access to the instance, for provisioning with `remote-exec` later. Remember `var.public_key_path` refers to a public key on our local machine.


```terraform
resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"
    host = "${self.public_ip}"
    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.default.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start",
    ]
  }
  ```

  Finally the instance is defined. In this case we're just installing and starting `nginx`, via the `remote-exec` to prove it all hangs together.

  It needs a public IP in order to do that provisioning; it also needs the key to be added via `key-name` and to be tied to its security group. The `ami` definition looks a bit odd, being done by a `lookup`.
  
  This is to support the region changing - [`ami`](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html)'s are specific to a region. The default for the `aws_amis` variable [defines the correct ami id for a handful of regions](https://github.com/terraform-providers/terraform-provider-aws/blob/master/examples/two-tier/variables.tf#L21).

  ```terraform
  variable "aws_amis" {
  default = {
    eu-west-1 = "ami-674cbc1e"
    us-east-1 = "ami-1d4e7a66"
    us-west-1 = "ami-969ab1f6"
    us-west-2 = "ami-8803e0f0"
  }
}
```

Note the comment on the subnet - it is more common to have the (private) instance on a separate subnet to the (public) ELB. Getting to that sounds like a good next exercise.








