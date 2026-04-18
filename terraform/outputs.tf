output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA."
  value       = module.eks.cluster_oidc_issuer_url
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the sandbox cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name to URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "argocd_port_forward_command" {
  description = "Port-forward the ArgoCD server to localhost:8080."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}

output "argocd_password_command" {
  description = "Print the initial ArgoCD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "grafana_port_forward_command" {
  description = "Port-forward Grafana to localhost:3000. Default login: admin / prom-operator."
  value       = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
}
