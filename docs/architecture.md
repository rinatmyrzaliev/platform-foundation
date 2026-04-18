# Architecture

## Diagram

```mermaid
flowchart TB
  subgraph AWS["AWS us-east-1"]
    IGW([Internet Gateway])

    subgraph VPC["VPC 10.0.0.0/16"]
      direction TB
      subgraph PUB["Public subnets (2 AZs)"]
        N1[(EC2 t3.medium SPOT<br/>AZ a)]
        N2[(EC2 t3.medium SPOT<br/>AZ b)]
      end
    end

    CP[[EKS control plane<br/>public endpoint, IRSA]]
    OIDC[[IAM OIDC provider<br/>token.actions.githubusercontent.com]]
    ROLE[[IAM role<br/>github-actions-platform]]
    ECR[[ECR<br/>orders / catalog / payments]]
  end

  subgraph Cluster["Kubernetes workloads"]
    direction TB
    ARGO[ArgoCD<br/>ClusterIP]
    CM[cert-manager]
    NGX[ingress-nginx<br/>NodePort]
    PROM[kube-prometheus-stack<br/>gp3 PVC 10 Gi]
    ES[external-secrets]
    CSI[aws-ebs-csi-driver<br/>IRSA]
  end

  DEV[[Developer laptop]]
  GH[[GitHub Actions<br/>repo:rinatmyrzaliev/*:*]]

  DEV -->|kubectl port-forward| CP
  DEV -->|terraform apply| AWS
  GH -->|OIDC AssumeRole| ROLE
  ROLE --> ECR
  ROLE --> CP

  IGW <--> PUB
  N1 --- CP
  N2 --- CP
  CP --- Cluster
  CSI -.IRSA.- OIDC
```

## Layer map

| Layer              | What lives here                                                              |
|--------------------|------------------------------------------------------------------------------|
| Networking         | 1 VPC, 2 public subnets, IGW. No private subnets, no NAT (ADR-001).          |
| Compute            | 1 EKS managed node group `workers-spot`, AL2023, t3.medium spot, scale 0..5. |
| Cluster services   | vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver (IRSA).                     |
| Platform addons    | argo-cd, cert-manager, ingress-nginx, kube-prometheus-stack, external-secrets. |
| Identity           | EKS OIDC provider for IRSA; separate IAM OIDC for GitHub Actions.            |
| Registry           | 3 ECR repos with scan-on-push and lifecycle policy.                          |

## Data & traffic flow

- **Developer → cluster**: `kubectl` hits the EKS public endpoint. ArgoCD/Grafana UIs are reached via `kubectl port-forward` (ADR-004).
- **Pod egress**: each worker has a public IP; pods egress through the node ENI straight to the IGW.
- **Pod → AWS APIs**: via IRSA. EBS CSI controller assumes `platform-sandbox-ebs-csi` for volume provisioning.
- **GitHub Actions → AWS**: the workflow exchanges its GitHub-issued OIDC token for STS credentials against `github-actions-platform`. That role has ECR power-user + `eks:DescribeCluster`/`ListClusters`, enough to push images and run `aws eks update-kubeconfig`.
- **Prometheus storage**: gp3 StorageClass (default) backs the 10 Gi PVC from `kube-prometheus-stack`. 7-day retention.

## What's wired but intentionally not exposed

- **ingress-nginx** runs as NodePort. Nothing maps the NodePort to the public internet by default — you'd open node SG rules explicitly to do that.
- **cert-manager** is installed but no `ClusterIssuer` is created yet. Add Let's Encrypt / ACM PCA issuers when you actually need certs.
- **external-secrets** runs without any `SecretStore` configured. Wire to AWS Secrets Manager / SSM Parameter Store per-workload when needed.
- **alertmanager** is enabled but has no receivers configured. Add Slack/PagerDuty routing in a follow-up values file.
