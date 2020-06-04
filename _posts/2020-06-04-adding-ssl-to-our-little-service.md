---
layout: post
title: Adding SSL to our little AWS service
date: 2020-06-04 15:47:40 +0100
author: Paul Wilson
categories: log terraform aws
---

Earlier today I [wrote a bit]({% post_url 2020-06-04-two-tier-elb-and-instance-in-separate-subnets %}) about separating the ELB and instance(s) into separate subnets and how we might make that useful. Potentially we could dive deeper into [ACL](https://docs.aws.amazon.com/AmazonS3/latest/dev/S3_ACLs_UsingACLs.html)s and/or routing tables and the [bastion](https://docs.aws.amazon.com/quickstart/latest/linux-bastion/architecture.html) pattern. We could start looking at Terraform modules,   Instead though, I want to press on towards getting something deployed.

These days, serving anything insecurely over the web is not acceptable. We need an SSL certificate and be configured to serve over _https_.

As we are on AWS it makes sense to use the [AWS Certificate Manager](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html) to obtain and manage the certificate. This part is manual:

1. Log on to the AWS console (as in the web interface)
1. Click the blue "Request a certificate" button, towards the top and left of the main page
1. Choose "Request a public certficiate"
1. Enter your chosen domain name and click "Next". (I used beta.correcthorsebatterystaple.com)
1. Choose DNS Validation.
1. Optionally tag your certificate with whatever, and "Review"
1. "Confirm and request"
1. Expand the domain. You'll be given a name and value to add to your DNS as a CNAME. If you happen to use [Amazon's Route 53](https://aws.amazon.com/route53/) you're golden. I don't and headed over to [DNSimple](https://dnsimple.com) an d added the record.
1. Hit "continue"
1. Keep refreshing and waiting. Hopefully validation will come your way.

Ok, back to the Terraform. We'll keep on using the Two Tier example. First we need to be able to refer to the certificate:

```terraform
data "aws_acm_certificate" "mycert" {
  domain = "beta.correcthorsebatterystaple.com"
  statuses = ["ISSUED"]
}
```

I love that you can find the certificate via the domain name. Arguably I should have used a variable for the domain, though.


We need to add ELB to support https over 443, with the certificate. We do this by adding a listener to `resource "aws_elb" "web"`

```terraform
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 443
    lb_protocol = "https"
    ssl_certificate_id = data.aws_acm_certificate.mycert.arn
  }
```

A few things to note
* the communication with the instance is still `http` on port 80
* use `arn` to get the `ssl_certificate_id` not `id`

Don't forget to open ope 443 in the security group for the ELB, `resource "aws_security_group" "elb" ` in our case:


```terraform
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
```

Run `terraform apply` and we can now serve our default `ngninx` page securely.

I pulled this example code into its own repo, if you want to [inspect it more fully](https://github.com/paulanthonywilson/examples-from-terraform-provider-aws/blob/4114b2258693580e0708223ae2ecf5a456c181cf/two-tier/main.tf).