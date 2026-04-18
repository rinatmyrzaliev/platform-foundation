# Cost breakdown

All prices are us-east-1 list, April 2026. Rounded to keep the math simple;
reconcile against Cost Explorer, not this file.

## Per-resource monthly estimate (24/7)

| Line item                          | Unit price               | Qty / sizing                 | Monthly       | Notes |
|------------------------------------|--------------------------|------------------------------|---------------|-------|
| EKS control plane                  | $0.10 / hr               | 1 cluster                    | **$72.00**    | Not reducible. Only "off" state is destroy. |
| Worker EC2 (t3.medium spot)        | ~$0.012 / hr             | 2 nodes                      | **$17.30**    | Spot ~70% below $0.0416 on-demand. |
| EBS gp3 — node root volumes        | $0.08 / GB-mo            | 2 × 20 GiB                   | **$3.20**     | Default AL2023 AMI root volume. |
| EBS gp3 — Prometheus PVC           | $0.08 / GB-mo            | 1 × 10 GiB                   | **$0.80**     | From `prometheus.storageSpec`. Retained across node restarts. |
| ECR storage                        | $0.10 / GB-mo            | ~2 GiB across 3 repos        | **$0.20**     | Lifecycle keeps last 10 tags + 7-day untagged. |
| Data transfer — out to internet    | $0.09 / GB (first 10 TB) | ~5 GiB / mo (low)            | **$0.45**     | No NAT (see ADR-001); egress is direct from node ENIs. |
| Public IPv4 addresses (node ENIs)  | $0.005 / hr each         | 2 node IPs                   | **$7.20**     | AWS started charging for public IPv4 in Feb 2024. |
| **Total (24/7, nodes always on)**  |                          |                              | **~$101 / mo**| |

## Expected 14-day sandbox total

Target: **$100–125** across two weeks of intermittent use.

Assumptions:
- Cluster exists for the full 14 days: control plane = $72/mo × 14/30 ≈ **$33.60**
- Nodes run ~10 hr/day on weekdays, off on weekends (via `scale-down.sh`):
  10 hr × 10 weekdays = 100 hr × $0.012 × 2 nodes ≈ **$2.40**
- EBS volumes bill 24/7 regardless of node state:
  (40 GiB root + 10 GiB prom) × $0.08/mo × 14/30 ≈ **$1.87**
- Public IPv4 only bills while nodes are up: 100 hr × $0.005 × 2 ≈ **$1.00**
- ECR + data transfer: **~$0.50**
- **Subtotal:** ~$39.40

The target of $100–125 leaves headroom for:
- Forgetting to run `scale-down.sh` a few nights (each skipped night ≈ $0.60 EC2 + $0.24 EIP).
- Experimenting with a bigger node group size for a demo.
- One accidental ALB or NAT Gateway left running (add $16–32 before being caught).

## Biggest levers if cost creeps up

1. **Control plane**: the only way to zero it is `terraform destroy`. Everything else is just the nodes.
2. **Forgetting scale-down**: an EIP left attached overnight costs more than the spot node it's attached to.
3. **Prometheus retention**: raising `retention` from 7d pushes the PVC size up.
4. **Accidentally creating a LoadBalancer Service**: any `Service type=LoadBalancer` provisions an NLB/ALB. ADR-003 explicitly avoids this; check `kubectl get svc -A` if costs spike.
5. **Leaked public IPs** from orphaned ENIs: check `aws ec2 describe-addresses` if the cluster has been destroyed and re-created several times.

## What's explicitly NOT in this estimate

- CloudWatch Logs for the EKS control plane — *not* enabled here. Each log type adds ingestion + retention cost.
- AWS WAF, GuardDuty, Security Hub — all off for the sandbox.
- A NAT Gateway — deliberately off, see ADR-001.
- An ALB — deliberately off, see ADR-003.
