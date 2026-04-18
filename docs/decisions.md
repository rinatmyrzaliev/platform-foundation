# Architecture Decision Records

Each ADR captures a cost-vs-production trade-off made in this sandbox so it
can be explained during interviews. The production-shaped alternative is
called out in every entry.

---

## ADR-001: Public subnets only, no NAT Gateway

**Status:** Accepted
**Context:** A NAT Gateway in us-east-1 costs ~$0.045/hr (~$32/mo) plus
$0.045/GB processed. For a cluster that runs on-and-off for two weeks, NAT is
often the single largest line item after the control plane itself.

**Decision:** The VPC has two public subnets (10.0.1.0/24, 10.0.2.0/24) and
no private subnets or NAT Gateway. Worker nodes get public IPs
(`map_public_ip_on_launch = true`) and reach the internet directly through
the Internet Gateway. The required EKS subnet tags
(`kubernetes.io/role/elb = 1`,
`kubernetes.io/cluster/platform-sandbox = shared`) are on the public subnets.

**Consequences:**
- Saves ~$32/mo fixed + per-GB data processing.
- Nodes are internet-reachable. Mitigation: EKS-managed security groups only
  open the API/VXLAN traffic needed; no `0.0.0.0/0` ingress on node SGs;
  no workloads expose NodePorts to the internet (ingress-nginx is only used
  inside the cluster and reached via port-forward).
- Pod egress goes via node ENI directly to IGW. This is fine for demos but
  means every pod's egress traffic is attributable to a node public IP.

**Production alternative:** Private subnets with either a NAT Gateway
(simplest) or VPC endpoints for S3/ECR/STS/EKS/EC2 (cheaper at scale, more
moving parts). Workers get private IPs only; no direct internet reachability.

---

## ADR-002: Spot instances for worker nodes

**Status:** Accepted
**Context:** On-demand t3.medium in us-east-1 is ~$0.0416/hr; spot for the
same instance typically runs $0.010–0.014/hr — roughly 70% cheaper.

**Decision:** The single managed node group (`workers-spot`) uses
`capacity_type = SPOT` with `instance_types = ["t3.medium"]`, scale 0..5,
desired 2.

**Consequences:**
- ~$15–20/mo when running vs ~$60/mo on-demand.
- Nodes can be reclaimed by AWS with a 2-minute warning. For the demo
  workloads this is acceptable; if it becomes disruptive, Karpenter or a
  mixed node group (1 on-demand + N spot) is the next step.
- AL2023 AMI + EKS managed node group handles draining on interruption.

**Production alternative:** On-demand or Savings Plan-backed capacity for
baseline, Karpenter provisioning spot for burst. Or a mixed node group with
a `SPOT_ALLOCATION_STRATEGY` set to `capacity-optimized`.

---

## ADR-003: NodePort for ingress-nginx, no AWS Load Balancer Controller

**Status:** Accepted
**Context:** An ALB in us-east-1 is ~$0.0225/hr base (~$16–18/mo) plus LCU
charges. The AWS Load Balancer Controller also needs IRSA wiring. For a
sandbox, neither is worth the money when we access apps via port-forward or
the node's public IP during testing.

**Decision:** ingress-nginx's controller Service is `NodePort`. No
`aws-load-balancer-controller` is installed. Test traffic hits
`http://<node-public-ip>:<nodeport>` or goes through `kubectl port-forward`.

**Consequences:**
- Saves ~$18/mo base plus LCU charges.
- No TLS termination at the edge — cert-manager still runs so we can issue
  certs inside the cluster, but there's no ALB doing ACM-based TLS.
- NodePort ranges must be reachable if you want to hit apps from outside;
  in this sandbox node SGs deliberately don't open NodePort range to
  `0.0.0.0/0`, so external access is explicit and temporary.

**Production alternative:** `aws-load-balancer-controller` installed via
IRSA; `Service type=LoadBalancer` provisions NLBs for L4 and Ingress objects
provision ALBs for L7. Add WAFv2 in front of the ALB for app-layer
protection.

---

## ADR-004: ClusterIP + port-forward for ArgoCD and Grafana

**Status:** Accepted
**Context:** ArgoCD and Grafana both ship well-known default credentials.
Exposing them on the public internet — even behind TLS — without SSO invites
credential-stuffing attacks and appears regularly in bug bounty reports.

**Decision:** ArgoCD server Service and Grafana Service are both
`ClusterIP`. Access is exclusively via `kubectl port-forward`. The
`argocd_port_forward_command` and `grafana_port_forward_command` outputs
print the exact commands.

**Consequences:**
- Zero public exposure of the platform control planes.
- No ALB/NLB needed for them — additional cost saving on top of ADR-003.
- Inconvenience: to click around Grafana you need a working kubeconfig and
  a port-forward running. Acceptable for a single-operator sandbox.

**Production alternative:** OIDC-authenticated Ingress (e.g., ArgoCD behind
`argocd-server --insecure=false` with OIDC pointed at Okta/GitHub, Grafana
using its native OIDC integration), TLS via cert-manager + ACM,
NetworkPolicy to lock down access paths, audit logging shipped off-cluster.

---

## ADR-005: Terraform-managed Helm releases at bootstrap

**Status:** Accepted (interim)
**Context:** A real GitOps platform lets ArgoCD manage all workload and
platform-level Helm releases (app-of-apps). But before ArgoCD exists, *something*
has to install ArgoCD — that's the bootstrap problem.

**Decision:** Terraform installs all five bootstrap addons (argo-cd,
cert-manager, ingress-nginx, kube-prometheus-stack, external-secrets) as
`helm_release` resources gated by `depends_on = [module.eks]`. Chart
versions are pinned.

**Consequences:**
- Clear, reproducible bootstrap with `terraform apply`. No manual kubectl.
- Config drift: if someone edits a Helm release in the cluster, Terraform
  will want to revert it on next apply. For a sandbox that's fine; for a
  real platform you'd hand these over to ArgoCD.
- Terraform has to keep a live connection to the cluster on every plan,
  which slows iteration.

**Production evolution:** Use Terraform only for the infrastructure
(VPC/EKS/IAM/ECR) and a *minimal* ArgoCD bootstrap. Move all other addons
into an ArgoCD `ApplicationSet` / app-of-apps repo. Planned as the "Golden
Path" follow-up project.

---

## ADR-006: Local Terraform state

**Status:** Accepted (sandbox only)
**Context:** Remote state with S3 + DynamoDB locking is the standard for any
team or CI-driven workflow. But it's a chicken-and-egg problem for a solo
sandbox: you need state infrastructure *before* you have any infrastructure,
which means a separate bootstrap stack just to hold state.

**Decision:** Terraform uses local state (`terraform.tfstate` in the
working directory). `versions.tf` contains a commented-out `backend "s3"`
block with migration instructions so the migration path is documented.

**Consequences:**
- Single-user only. No locking. State lives on one laptop.
- `.gitignore` covers `*.tfstate*` so it's never committed.
- Migration is `terraform init -migrate-state` after uncommenting the
  backend block and creating the bucket + DynamoDB table.

**Production alternative:** S3 bucket with versioning + SSE-KMS, DynamoDB
table for state locking, per-environment state keys, `terraform_remote_state`
data sources for cross-stack references. Created by a small `bootstrap/`
Terraform stack that is itself bootstrapped manually or via CloudFormation.
