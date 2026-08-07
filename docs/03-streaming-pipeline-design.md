# 03. Streaming Pipeline

## Overview

One Kinesis stream, `iot-sensor-data` — 1 shard, `PROVISIONED` mode, 24-hour retention. `ingestion-api` is the only producer. `stream-processor` and `alerting-service` are two independent consumers reading the same stream.

## One role per service, not one shared role

Every service gets its own IAM role through IRSA. Each role's trust policy only accepts `sts:AssumeRoleWithWebIdentity` from the specific Kubernetes ServiceAccount it belongs to, matched on the OIDC `sub` claim (`system:serviceaccount:iot-streaming:<name>`). A pod running as read-api's service account can't just borrow stream-processor's permissions by being in the same cluster.

Permissions on the stream, by service:

| Service | Kinesis permissions |
|---|---|
| ingestion-api | `PutRecord`, `PutRecords` |
| stream-processor | `GetRecords`, `GetShardIterator`, `DescribeStream`, `DescribeStreamSummary`, `ListShards` |
| alerting-service | same read set as stream-processor |
| read-api | none |

stream-processor also gets `PutItem`/`BatchWriteItem` on DynamoDB (see [data layer](04-data-layer-design.md)). alerting-service doesn't touch any AWS write API at all — its output is a Slack webhook call, not another AWS resource.

## Two consumers, no shared checkpoint

stream-processor and alerting-service each open their own `LATEST` shard iterator instead of coordinating through a shared consumer group. Simpler to build, at the cost of both services re-reading the same records independently. It also means overlapping pods during a rollout can both grab a fresh iterator and process the same record twice — alerting-service handles that with in-memory sequence-number dedup rather than anything at the Kinesis level.
