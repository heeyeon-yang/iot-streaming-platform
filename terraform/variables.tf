variable "aws_region" {
  description = "리소스를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름 앞에 붙일 프로젝트 접두사"
  type        = string
  default     = "iot-streaming"
}

variable "vpc_cidr" {
  description = "VPC의 IP 주소 대역"
  type        = string
  default     = "10.1.0.0/16"
}

variable "node_instance_type" {
  description = "EKS 워커 노드로 사용할 EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"
}
