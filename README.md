# iot-streaming-platform

IoT sensor data pipeline running on EKS — devices push readings in, Kinesis moves them through, and a set of containerized services process, store, and alert on them. Built on AWS (ap-northeast-2) with Terraform.

Status: work in progress. Infrastructure and all four services are deployed; still debugging the Kinesis → DynamoDB read path.

## Why I built this

QuizLab was managed and serverless — Lambda, RDS, ElastiCache. This one runs on self-managed containers on Kubernetes instead. Different infrastructure model, same underlying AWS skill set.

## Architecture

Four services on EKS, one namespace:

- **ingestion-api** (Node/Express) — receives sensor readings over HTTP, writes them to Kinesis
- **stream-processor** (Python) — polls Kinesis, persists readings to DynamoDB
- **alerting-service** (Python) — polls Kinesis independently, checks readings against a threshold, fires a Slack webhook when exceeded
- **read-api** (Node/Express) — read-only endpoint over DynamoDB for the dashboard

API-facing services are Node; processing/decision services are Python.

Everything sits in its own VPC (separate from QuizLab's), inside a single EKS cluster with one managed node group. Each service has its own IAM role scoped to exactly what it needs via IRSA, rather than one shared node role with broad permissions.

Devices themselves are simulated with a local script — no real hardware involved.

## Infrastructure

One Terraform directory covers VPC, EKS, ECR, DynamoDB, Kinesis, and the IAM roles for IRSA. Kubernetes manifests (namespace, service accounts, deployments, services) are plain YAML applied by hand for now. ArgoCD is next.

## Stack

Terraform, AWS VPC/EKS/ECR/DynamoDB/Kinesis, Node.js (Express), Python, Docker, kubectl.

Helm, ArgoCD, and Prometheus/Grafana are planned next steps, not yet in place.
