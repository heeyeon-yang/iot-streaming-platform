resource "aws_kinesis_stream" "sensor_data" {
  name             = "iot-sensor-data"
  shard_count      = 1
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Project = "iot-streaming"
  }
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.sensor_data.name
}

output "kinesis_stream_arn" {
  value = aws_kinesis_stream.sensor_data.arn
}
