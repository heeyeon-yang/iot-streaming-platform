module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = 1

      # v20 모듈에서 Custom User Data 주입하여 kubelet max-pods 재정의
      user_data_template_path = ""
      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        set -ex
        cat << 'USERDATA' > /etc/eks/bootstrap.sh
        #!/bin/bash
        /etc/eks/bootstrap.sh --use-max-pods false --kubelet-extra-args '--max-pods=110' "$@"
        USERDATA
      EOT
    }
  }

  tags = {
    Project = var.project_name
  }
}
