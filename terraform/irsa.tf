locals {
  k8s_namespace = "iot-streaming"
}

# Trust policy shared shape: only pods running as a specific K8s service account
# in our namespace can assume these roles — this is what makes IRSA safe.
data "aws_iam_policy_document" "assume_role_ingestion_api" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.k8s_namespace}:ingestion-api"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingestion_api" {
  name               = "iot-streaming-ingestion-api"
  assume_role_policy = data.aws_iam_policy_document.assume_role_ingestion_api.json
}

resource "aws_iam_role_policy" "ingestion_api" {
  name = "kinesis-put"
  role = aws_iam_role.ingestion_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
      Resource = aws_kinesis_stream.sensor_data.arn
    }]
  })
}

# stream-processor: reads Kinesis, writes DynamoDB
data "aws_iam_policy_document" "assume_role_stream_processor" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.k8s_namespace}:stream-processor"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "stream_processor" {
  name               = "iot-streaming-stream-processor"
  assume_role_policy = data.aws_iam_policy_document.assume_role_stream_processor.json
}

resource "aws_iam_role_policy" "stream_processor" {
  name = "kinesis-read-dynamodb-write"
  role = aws_iam_role.stream_processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.sensor_data.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
        Resource = aws_dynamodb_table.sensor_readings.arn
      }
    ]
  })
}

# alerting-service: reads Kinesis only
data "aws_iam_policy_document" "assume_role_alerting_service" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.k8s_namespace}:alerting-service"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alerting_service" {
  name               = "iot-streaming-alerting-service"
  assume_role_policy = data.aws_iam_policy_document.assume_role_alerting_service.json
}

resource "aws_iam_role_policy" "alerting_service" {
  name = "kinesis-read"
  role = aws_iam_role.alerting_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:ListShards"
      ]
      Resource = aws_kinesis_stream.sensor_data.arn
    }]
  })
}

# read-api: reads DynamoDB only
data "aws_iam_policy_document" "assume_role_read_api" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.k8s_namespace}:read-api"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "read_api" {
  name               = "iot-streaming-read-api"
  assume_role_policy = data.aws_iam_policy_document.assume_role_read_api.json
}

resource "aws_iam_role_policy" "read_api" {
  name = "dynamodb-read"
  role = aws_iam_role.read_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
      Resource = aws_dynamodb_table.sensor_readings.arn
    }]
  })
}

output "irsa_role_arns" {
  value = {
    "ingestion-api"    = aws_iam_role.ingestion_api.arn
    "stream-processor" = aws_iam_role.stream_processor.arn
    "alerting-service" = aws_iam_role.alerting_service.arn
    "read-api"         = aws_iam_role.read_api.arn
  }
}
