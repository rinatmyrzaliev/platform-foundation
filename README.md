# platform-foundation

Cost-optimized AWS EKS sandbox for DevOps / Platform / SRE portfolio work.
Built to stay under **$150 for 2 weeks** of intermittent use while being
realistic enough to demonstrate senior-level platform skills.

Every cost-vs-production trade-off is documented in
[`docs/decisions.md`](docs/decisions.md) as a numbered ADR so it can be
defended in an interview.

## What this provisions

- **Networking** — VPC with 2 public subnets in 2 AZs. No NAT Gateway (ADR-001).
- **EKS** — `platform-sandbox` cluster, Kubernetes 1.34, public endpoint, IRSA on.
- **Nodes** — 1 managed node group on spot t3.medium, scale 0..5, AL2023 AMI.
- **Managed addons** — vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver (with IRSA).
- **Platform addons (Helm)** — argo-cd, cert-manager, ingress-nginx (NodePort, ADR-003), kube-prometheus-stack (gp3 PVC, 7d retention), external-secrets.
- **IAM** — GitHub Actions OIDC provider + `github-actions-platform` role trusting any repo owned by `rinatmyrzaliev`.
- **ECR** — 3 private repos (`orders-service`, `catalog-service`, `payments-service`) with scan-on-push and lifecycle policies.

Full diagram: [`docs/architecture.md`](docs/architecture.md).
Cost math: [`docs/cost-breakdown.md`](docs/cost-breakdown.md).

## Prerequisites

| Tool       | Minimum version | Notes |
|------------|-----------------|-------|
| terraform  | 1.6.0           | Pinned `< 2.0.0` in `versions.tf`. |
| aws CLI    | 2.15            | Must be logged in: `aws sts get-caller-identity`. |
| kubectl    | 1.32            | Client within one minor of the 1.34 control plane. |
| helm       | 3.14            | Only needed if you manage releases outside Terraform. |

AWS account and region: any account you own; scripts default to
`us-east-1`. Override with `AWS_REGION`.

## Quickstart

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — github_username is required, everything else has a default

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Apply takes ~15–20 minutes on a cold run (VPC + EKS control plane + node group + 5 Helm releases).

## Daily workflow

```bash
# Morning — bring nodes back up (control plane stays on 24/7)
./scripts/scale-up.sh

# ...work...

# Evening — scale the node group to 0 to stop EC2 spot + public-IPv4 charges
./scripts/scale-down.sh
```

Scaling to 0 saves ~$0.60/day EC2 + ~$0.24/day public-IPv4. The control
plane still bills (~$2.40/day); the only way to fully zero it is
`terraform destroy`.

## Access ArgoCD

```bash
# One terminal — port-forward
kubectl -n argocd port-forward svc/argocd-server 8080:443

# Another terminal — grab the initial password
./scripts/get-argocd-password.sh
```

Then open <https://localhost:8080>, log in as `admin` with the password.
Rotate the password immediately and delete the
`argocd-initial-admin-secret` Secret.

## Access Grafana

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open <http://localhost:3000>. Default credentials from `kube-prometheus-stack`
are `admin` / `prom-operator` — change them on first login.

## GitHub Actions integration

The `github_actions_role_arn` output is the role your workflows should
assume. Minimal workflow snippet:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-actions-platform
          aws-region: us-east-1
      - run: aws eks update-kubeconfig --name platform-sandbox
      - run: aws ecr get-login-password | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

## Teardown

```bash
cd terraform
terraform destroy
```

The destroy takes ~10 minutes and removes **everything**, including the
ECR repos (and any images in them). ECR deletion will fail if the repos
contain images — add `force_delete = true` to the resource block if you
want teardown to nuke images too.

## Layout

```
platform-foundation/
├── README.md                    ← you are here
├── .gitignore
├── terraform/                   ← all IaC
│   ├── versions.tf              ← terraform + provider versions, remote-state migration notes
│   ├── providers.tf             ← aws / helm / kubernetes providers
│   ├── variables.tf
│   ├── outputs.tf
│   ├── main.tf                  ← locals + shared data sources
│   ├── vpc.tf                   ← terraform-aws-modules/vpc/aws
│   ├── eks.tf                   ← terraform-aws-modules/eks/aws + EBS CSI IRSA role
│   ├── iam-github-oidc.tf       ← GitHub Actions OIDC provider + role
│   ├── ecr.tf                   ← 3 private repos + lifecycle policy
│   ├── addons.tf                ← Helm releases for platform addons
│   └── terraform.tfvars.example
├── scripts/
│   ├── scale-down.sh
│   ├── scale-up.sh
│   ├── get-kubeconfig.sh
│   └── get-argocd-password.sh
└── docs/
    ├── architecture.md          ← mermaid diagram + layer map
    ├── cost-breakdown.md        ← itemized monthly + 14-day estimate
    └── decisions.md             ← ADR-001 through ADR-006
```
