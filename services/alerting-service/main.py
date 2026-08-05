import json
import os
import time
import urllib.request
from collections import deque

import boto3

from health import start_health_server, mark_unhealthy

AWS_REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
STREAM_NAME = os.environ.get("KINESIS_STREAM_NAME", "iot-sensor-stream")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "5"))
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")

# Threshold per sensor type. Anything outside [min, max] triggers an alert.
# Hardcoded for now; move to a config map once there's more than a couple of sensor types.
THRESHOLDS = {
    "temperature": {"min": 0, "max": 40},
    "humidity": {"min": 10, "max": 90},
}

kinesis = boto3.client("kinesis", region_name=AWS_REGION)

# Rolling restarts briefly run old and new pods side by side, and both call
# get_shard_iterator with LATEST independently. That can hand out overlapping
# records for a few seconds around the restart. Track recently-seen sequence
# numbers to drop duplicates instead of double-alerting.
DEDUP_WINDOW_SIZE = 500
_seen_sequence_numbers = deque(maxlen=DEDUP_WINDOW_SIZE)
_seen_sequence_number_set = set()


def is_duplicate(sequence_number):
    if sequence_number in _seen_sequence_number_set:
        return True

    if len(_seen_sequence_numbers) == DEDUP_WINDOW_SIZE:
        oldest = _seen_sequence_numbers.popleft()
        _seen_sequence_number_set.discard(oldest)

    _seen_sequence_numbers.append(sequence_number)
    _seen_sequence_number_set.add(sequence_number)
    return False


def get_shard_iterators():
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


def send_slack_alert(message):
    if not SLACK_WEBHOOK_URL:
        print(f"[no webhook configured] {message}")
        return

    body = json.dumps({"text": message}).encode("utf-8")
    request = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=body,
        headers={"Content-Type": "application/json"},
    )

    try:
        urllib.request.urlopen(request, timeout=5)
    except Exception as err:
        print(f"Failed to send Slack alert: {err}")


def check_threshold(reading):
    sensor_type = reading.get("sensorType")
    value = reading.get("value")
    threshold = THRESHOLDS.get(sensor_type)

    if threshold is None:
        return

    if value < threshold["min"] or value > threshold["max"]:
        message = (
            f":warning: {reading['deviceId']} reported {sensor_type}={value}, "
            f"outside expected range [{threshold['min']}, {threshold['max']}]"
        )
        print(message)
        send_slack_alert(message)


def process_record(record):
    if is_duplicate(record["SequenceNumber"]):
        return

    payload = json.loads(record["Data"])

    required_fields = ("deviceId", "sensorType", "value")
    if not all(field in payload for field in required_fields):
        print(f"Skipping malformed record: {payload}")
        return

    check_threshold(payload)


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
    print(f"alerting-service started, polling stream '{STREAM_NAME}' every {POLL_INTERVAL_SECONDS}s")

    try:
        poll_loop()
    except Exception as err:
        print(f"Fatal error in poll loop: {err}")
        mark_unhealthy()
        raise


if __name__ == "__main__":
    main()
