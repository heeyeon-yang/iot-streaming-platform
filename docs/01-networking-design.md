# 01. Networking

## Overview

The VPC is `10.1.0.0/16`, split into 2 public and 2 private subnets across `ap-northeast-2a` and `ap-northeast-2b`. EKS nodes sit in the private subnets; the public subnets exist only to give the NAT gateway somewhere to sit.

## Two AZs, not one

This isn't about resilience — it's just what EKS asks for. The control plane needs subnets in at least two AZs to come up at all, and the node group's `min_size` is 1, so there's no actual multi-AZ workload story here. The subnet layout just happens to already support it if that changes later.

## No second NAT Gateway

Both private subnets share a single NAT gateway instead of one each. Two would double the NAT cost of a cluster that gets destroyed at the end of every session anyway — the AZ-level redundancy a second one buys isn't worth much when nothing runs long enough for an outage to matter.

## ELB subnet tags, unused for now

Private subnets are tagged `kubernetes.io/role/internal-elb`, public ones `kubernetes.io/role/elb`, so a load balancer controller could auto-discover the right subnets if one gets added later. Nothing uses them yet — both exposed services are reached with `kubectl port-forward`.
