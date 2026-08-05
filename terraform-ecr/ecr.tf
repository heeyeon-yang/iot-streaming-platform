locals {
  ecr_repositories = [
    "ingestion-api",
    "stream-processor",
    "alerting-service",
    "read-api"
  ]
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(local.ecr_repositories)
  name                 = "iot-streaming-platform/${each.value}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the last 10 images per repo so old builds don't quietly pile up storage cost.
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "ecr_repository_urls" {
  description = "ECR repository URLs, keyed by service name"
  value       = { for name, repo in aws_ecr_repository.services : name => repo.repository_url }
}
