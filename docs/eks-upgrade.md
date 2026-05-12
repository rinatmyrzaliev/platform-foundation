# EKS Cluster Upgrade Runbook

## Overview

Step-by-step runbook for upgrading an EKS cluster one minor version with zero service disruption.  
Tested on: **EKS 1.34 → 1.35** (May 11, 2026) on cluster `platform-sandbox` (us-east-1).

**Total time:** ~40 minutes  
**Downtime:** Zero — all services remained available throughout.

---

## Prerequisites

- `kubectl`, `aws` CLI, `terraform` configured and authenticated
- [`pluto`](https://github.com/FairwindsOps/pluto) installed for deprecated API detection
- All workloads running and healthy before starting
- PodDisruptionBudgets in place for critical services

---

## Phase 1 — Pre-Upgrade Checks

### 1.1 Scan for deprecated APIs

```bash
pluto detect-all-in-cluster
```

Fix any deprecated APIs **before** upgrading. An API removed in the target version will break workloads silently.

### 1.2 Check EKS upgrade insights

```bash
aws eks list-insights --cluster-name <CLUSTER_NAME>
```

All checks must show `PASSING`. If any show `ERROR` or `WARNING`, resolve before proceeding.

### 1.3 Check current add-on versions

```bash
for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
  echo "$addon: $(aws eks describe-addon --cluster-name <CLUSTER_NAME> --addon-name $addon --query 'addon.addonVersion' --output text)"
done
```

### 1.4 Check compatible add-on versions for target

```bash
TARGET_VERSION="1.35"
for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
  echo "$addon: $(aws eks describe-addon-versions --kubernetes-version $TARGET_VERSION --addon-name $addon --query 'addons[0].addonVersions[0].addonVersion' --output text)"
done
```

### 1.5 Verify PDBs are in place

```bash
kubectl get pdb -A
```

Every critical service should have a PDB. Services without PDBs risk all pods being evicted simultaneously during node rotation.

### 1.6 Save pre-upgrade state

```bash
kubectl get nodes -o wide > pre-upgrade-nodes.txt
kubectl get pods -A -o wide > pre-upgrade-pods.txt
kubectl version > pre-upgrade-version.txt
```

---

## Phase 2 — Control Plane Upgrade

> **Note:** In production, this step is done through Terraform/IaC (change `cluster_version` variable, PR, review, apply). The manual command is shown here for understanding what happens under the hood.

```bash
aws eks update-cluster-version \
  --name <CLUSTER_NAME> \
  --kubernetes-version <TARGET_VERSION>
```

Monitor progress:

```bash
watch "aws eks describe-update --name <CLUSTER_NAME> --update-id <UPDATE_ID> --query 'update.status' --output text"
```

**Expected duration:** ~10-15 minutes.  
**Impact:** Zero. AWS does a rolling replacement of API server instances behind a load balancer. Workloads continue running. Brief `kubectl` timeouts are possible but normal.

**Important:** You cannot roll back a control plane upgrade. The strategy for failures at this stage is "fix forward."

---

## Phase 3 — Add-Ons and Node Group Upgrade (via Terraform)

Update the Kubernetes version variable in Terraform:

```hcl
# terraform.tfvars
kubernetes_version = "1.35"  # was "1.34"
```

If add-ons use `most_recent = true`, Terraform will automatically select compatible versions. Then:

```bash
terraform plan    # Review changes — expect add-on updates + node group update
terraform apply   # Apply after review
```

### What Terraform does

1. **Add-on upgrades** (in-place, minimal disruption):
   - VPC CNI → new version (pod networking)
   - kube-proxy → new version (service routing)
   - CoreDNS → new version (DNS resolution)

2. **Node group update** (rolling replacement):
   - EKS launches new nodes with the 1.35 AMI
   - Old nodes are cordoned (no new pods scheduled)
   - Old nodes are drained (existing pods evicted, respecting PDBs)
   - Once pods are rescheduled on new nodes, old nodes are terminated

### Monitoring during node rollout

```bash
# Terminal 1 — watch nodes
kubectl get nodes -w

# Terminal 2 — watch pods moving
kubectl get pods -A -w

# Terminal 3 — watch PDB status
kubectl get pdb -A -w
```

**Expected duration:** ~15-20 minutes for node rotation.  
**Impact:** Zero if PDBs are configured correctly. Pods are rescheduled before old nodes are removed.

---

## Phase 4 — Post-Upgrade Validation

### 4.1 Verify versions

```bash
kubectl version
kubectl get nodes -o wide  # All nodes should show target version
```

### 4.2 Verify all pods healthy

```bash
kubectl get pods -A | grep -v Running
```

Should return only the header line (no unhealthy pods).

### 4.3 Verify add-on versions

```bash
for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver; do
  echo "$addon: $(aws eks describe-addon --cluster-name <CLUSTER_NAME> --addon-name $addon --query 'addon.addonVersion' --output text)"
done
```

### 4.4 Verify PDBs intact

```bash
kubectl get pdb -A
```

### 4.5 Check SLO/monitoring dashboards

- Confirm burn-rate alerts stayed green throughout the upgrade
- Check Grafana dashboards for any error rate spikes
- Review Alertmanager for any alerts that fired during the window

### 4.6 Compare with pre-upgrade state

```bash
kubectl get nodes -o wide > post-upgrade-nodes.txt
kubectl get pods -A -o wide > post-upgrade-pods.txt
diff pre-upgrade-nodes.txt post-upgrade-nodes.txt
diff pre-upgrade-pods.txt post-upgrade-pods.txt
```

---

## Phase 5 — Cleanup

```bash
# Commit Terraform change
cd platform-foundation/terraform
git add terraform.tfvars
git commit -m "chore: upgrade EKS cluster to <TARGET_VERSION>"
git push

# Remove temp files
rm pre-upgrade-*.txt post-upgrade-*.txt
```

---

## Rollback Plan

| Component | Rollback possible? | Strategy |
|---|---|---|
| Control plane | No | Fix forward. AWS does not support downgrading. |
| Add-ons | Yes | Pin to previous version in Terraform and apply. |
| Node group | Yes | Stop the rollout. Old nodes stay until you remove them. |
| Workloads | Yes | ArgoCD reverts to last known-good Git state. |

---

## Lessons Learned (1.34 → 1.35)

- `pluto detect-all-in-cluster` showed no deprecated APIs — clean upgrade path
- EKS Insights (5 checks) all passed before upgrade — useful automated pre-flight
- Control plane upgrade completed in ~8 minutes with zero `kubectl` disruption
- PDBs with `maxUnavailable: 1` allowed pods to drain one at a time across nodes — services with `ALLOWED DISRUPTIONS: 0` waited until a new replica was scheduled before evicting
- Using `most_recent = true` for add-ons in Terraform simplifies version management — Terraform picks the right version automatically
- Karpenter-provisioned nodes were replaced alongside managed node group nodes seamlessly
- Total upgrade wall-clock time: ~40 minutes from first command to final validation

---

## Checklist Summary

- [ ] `pluto detect-all-in-cluster` — no deprecated APIs
- [ ] `aws eks list-insights` — all checks PASSING
- [ ] Add-on compatibility verified for target version
- [ ] PDBs in place for all critical services
- [ ] Pre-upgrade state saved
- [ ] Control plane upgraded
- [ ] Add-ons upgraded (via Terraform)
- [ ] Node group rolled (via Terraform)
- [ ] All pods Running, zero restarts
- [ ] Add-on versions match target
- [ ] SLO dashboards green
- [ ] Terraform change committed and pushed