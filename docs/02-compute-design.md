# 02. Compute

## Overview

EKS runs on the `terraform-aws-modules/eks/aws` module (`~> 20.0`), cluster version `1.34`, one managed node group on `t3.small` instances (min 1, max 3, desired 1). Four services run in the `iot-streaming` namespace, each with its own Deployment, ServiceAccount, and IAM role.

## Cluster creator admin permissions, explicitly on

As of module v20, creating the cluster no longer grants cluster-admin to whoever ran `terraform apply` — that used to be automatic. `enable_cluster_creator_admin_permissions = true` turns it back on manually; without it, `kubectl` access breaks the moment the cluster comes up. `enable_irsa = true` sits next to it, since IRSA needs the OIDC provider that flag sets up.

## ECR in its own Terraform state

Images are built locally and pushed to ECR, one repository per service, each with scan-on-push and a lifecycle policy that keeps only the last 10 images. ECR lives in `terraform-ecr/`, a separate directory with separate state from the rest of compute. The cluster gets destroyed and rebuilt every session to avoid idle cost; images don't need to follow that same lifecycle, so splitting the state keeps `terraform destroy` in the main directory from taking the images down with it.

## Small resource requests, on purpose

Four services share `t3.small` nodes, so each Deployment asks for `100m`/`128Mi` and caps at `250m`/`256Mi`. That's tight, but it's what fits four containers plus system pods on one or two small nodes without the node group needing to scale past 1.

## ClusterIP only, no load balancer

Only `ingestion-api` and `read-api` get a Kubernetes Service, both `ClusterIP`. Neither has a LoadBalancer or ingress in front of it — they're reached with `kubectl port-forward` for now. `stream-processor` and `alerting-service` don't get a Service at all, since neither accepts inbound traffic; they only poll Kinesis.
