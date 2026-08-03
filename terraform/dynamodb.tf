resource "aws_dynamodb_table" "sensor_readings" {
  name         = "sensor-readings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "device_id"
  range_key    = "timestamp"

  attribute {
    name = "device_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = {
    Project = "iot-streaming"
  }
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.sensor_readings.name
}
