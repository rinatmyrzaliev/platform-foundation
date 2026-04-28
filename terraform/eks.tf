module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public endpoint only so kubectl / CI can reach the API without a bastion.
  # Private endpoint stays off to avoid needing VPC endpoints (see ADR-001).
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  # Grants the IAM principal running `terraform apply` cluster-admin via
  # EKS access entries — avoids the legacy aws-auth ConfigMap dance.
  enable_cluster_creator_admin_permissions = true

  # IRSA / OIDC provider for service accounts (EBS CSI, external-secrets, etc.).
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    workers-spot = {
      name = "workers-spot"

      instance_types = var.node_instance_types
      capacity_type  = "SPOT"

      min_size     = 0
      desired_size = var.node_desired_size
      max_size     = 5

      ami_type   = "AL2023_x86_64_STANDARD"
      subnet_ids = module.vpc.public_subnets

      labels = {
        node-role     = "worker"
        capacity-type = "spot"
      }

      tags = local.common_tags
    }
  }

  tags = local.common_tags
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}


# Fix: pod-to-pod traffic across nodes needs all-traffic rules between BOTH security groups.
# EKS module creates a cluster primary SG and a separate node SG.
# VPC CNI routes pod traffic through node ENIs, so both SGs must allow each other.

resource "aws_security_group_rule" "cluster_sg_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  description              = "Cluster SG self-referencing (pod networking)"
}

resource "aws_security_group_rule" "node_sg_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Node SG self-referencing (pod networking)"
}

resource "aws_security_group_rule" "cluster_to_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  description              = "Cluster SG to Node SG (pod networking)"
}

resource "aws_security_group_rule" "node_to_cluster" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = module.eks.node_security_group_id
  description              = "Node SG to Cluster SG (pod networking)"
}
