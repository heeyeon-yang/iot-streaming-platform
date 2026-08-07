# 04. Data Layer

## Overview

Sensor readings land in one DynamoDB table, `sensor-readings`, on-demand billing (`PAY_PER_REQUEST`). Hash key is `device_id` (string), range key is `timestamp` (number, epoch seconds).

## Timestamp as a number, not the string Kinesis carries

ingestion-api writes an ISO timestamp string to Kinesis, since that's the natural shape coming out of Node. DynamoDB's range key needs a number to make time-range queries cheap, so stream-processor converts it to epoch seconds — along with renaming the camelCase fields (`deviceId`, `sensorType`) to the snake_case the table expects — on the way in. The table schema doesn't bend to match what's on the stream; the translation happens in code instead.

## Read-only for read-api

read-api's role is scoped to `GetItem`, `Query`, and `Scan` — nothing else reaches this table.

## No separate Terraform state

Unlike ECR, this table doesn't get its own state. It only holds simulated readings, so losing it on every `terraform destroy` and reseeding with `simulator.sh` doesn't cost anything worth splitting the state for.
