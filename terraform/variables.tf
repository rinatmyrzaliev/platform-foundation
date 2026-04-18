variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Also used as tag/prefix for related resources."
  type        = string
  default     = "platform-sandbox"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version. Pinned to one minor below the latest EKS standard-support release."
  type        = string
  default     = "1.34"
}

variable "github_username" {
  description = "GitHub username/org whose repos may assume the github-actions-platform IAM role via OIDC."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group (spot)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group. Set to 0 via scripts/scale-down.sh to save cost overnight."
  type        = number
  default     = 2
}

variable "environment_tag" {
  description = "Environment tag applied to every resource."
  type        = string
  default     = "sandbox"
}
