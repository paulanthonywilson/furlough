---
layout: post
title: "Two tier: ELB and instance in separate subnets"
date: 2020-06-04 10:28:48 +0100
author: Paul Wilson
categories: log terraform aws
---

Following on from [yesterday]({% post_url 2020-06-03-two-tier-aws-with-terraform %}) I have just taken a brief look at putting the [ELB](https://docs.aws.amazon.com/elasticloadbalancing/) and instance on separate subnets, as seems to be good practice. It was all pretty straightforward.


```terraform
# Create a subnet for our ELB
resource "aws_subnet" "elb" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}
```

For neatness I renamed the "default" subnet to "elb" and changed the references throughout. As I'd destroyed everything after yesterday, I then performed a `terraform apply` recreated it all.

For kicks I tried changing the `cidr_block` to `10.0.2.0/24` to see what happens after running another `terraform apply`. What happens is that Terraform destroys the instance and then fails to desgtroy the subnet, possibly because it still had the ELB attached. Graceful shutdown (single ctrl c) didn't work, so it needs to be forced (second ctrl-c). A `terraform destroy` followed by `terraform apply` got everything up again.

Next create a new subnet ... 

```terraform
# And a subnet for the instance(s)
resource "aws_subnet" "instance" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = true
}
```

... and attach to the `resource "aws_instance" "web"`

```terraform
  subnet_id = aws_subnet.instance.id
```

`terraform apply` does works fine, and we can still route from the internet, though the ELB, to `ngnix` on the instance: we can still route from the "elb" subnet to the "instance" subnet. The reason is that the VPC's route table is, by default, assigned to each of its subnets - and that has two routes: `10.0.0.0/16` routing traffic locally across the VPC, and `0.0.0.0/0` for the world-wide internets.

So, what have we achieved with these two subnets? Not much, yet.

But by organising things this way it gives us an opportunity to add an extra layer of security. We could isolate the "instance" subnet from the outside world. Also we could add more fine-grained security with [Access Control Lists](https://docs.aws.amazon.com/AmazonS3/latest/dev/S3_ACLs_UsingACLs.html), the subnet version of Security Groups. 