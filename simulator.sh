#!/bin/bash
DEVICES=("device-001" "device-002" "device-003")
SENSOR_TYPES=("temperature" "humidity")

for i in $(seq 1 20); do
  DEVICE=${DEVICES[$((RANDOM % 3))]}
  TYPE=${SENSOR_TYPES[$((RANDOM % 2))]}

  if [ "$TYPE" == "temperature" ]; then
    VALUE=$((RANDOM % 15 + 15))   # 15~30도
  else
    VALUE=$((RANDOM % 40 + 30))   # 30~70%
  fi

  echo "[$i] sending: $DEVICE / $TYPE / $VALUE"
  curl -s -X POST http://localhost:3000/ingest \
    -H "Content-Type: application/json" \
    -d "{\"deviceId\":\"$DEVICE\",\"sensorType\":\"$TYPE\",\"value\":$VALUE}"
  echo ""
  sleep 1
done
