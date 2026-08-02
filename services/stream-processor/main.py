import json
import os
import time

import boto3

from health import start_health_server, mark_unhealthy

AWS_REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "iot-sensor-stream")
TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME", "sensor-readings")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "5"))

kinesis = boto3.client("kinesis", region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(TABLE_NAME)


def get_shard_iterators():
    """Return one iterator per shard, starting from the latest record."""
    stream_desc = kinesis.describe_stream(StreamName=STREAM_NAME)
    shard_ids = [s["ShardId"] for s in stream_desc["StreamDescription"]["Shards"]]

    iterators = {}
    for shard_id in shard_ids:
        response = kinesis.get_shard_iterator(
            StreamName=STREAM_NAME,
            ShardId=shard_id,
            ShardIteratorType="LATEST",
        )
        iterators[shard_id] = response["ShardIterator"]

    return iterators


def process_record(record):
    """Parse one Kinesis record and write it to DynamoDB."""
    payload = json.loads(record["Data"])

    required_fields = ("deviceId", "sensorType", "value", "timestamp")
    if not all(field in payload for field in required_fields):
        print(f"Skipping malformed record: {payload}")
        return

    table.put_item(Item=payload)
    print(f"Stored reading: {payload['deviceId']} / {payload['sensorType']} = {payload['value']}")


def poll_loop():
    iterators = get_shard_iterators()

    while True:
        for shard_id, shard_iterator in list(iterators.items()):
            response = kinesis.get_records(ShardIterator=shard_iterator, Limit=100)

            for record in response["Records"]:
                try:
                    process_record(record)
                except Exception as err:
                    print(f"Failed to process record: {err}")

            next_iterator = response.get("NextShardIterator")
            if next_iterator:
                iterators[shard_id] = next_iterator

        time.sleep(POLL_INTERVAL_SECONDS)


def main():
    start_health_server(port=8080)
    print(f"stream-processor started, polling stream '{STREAM_NAME}' every {POLL_INTERVAL_SECONDS}s")

    try:
        poll_loop()
    except Exception as err:
        print(f"Fatal error in poll loop: {err}")
        mark_unhealthy()
        raise


if __name__ == "__main__":
    main()
