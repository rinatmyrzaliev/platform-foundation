#!/usr/bin/env bash
# Scale the managed node group to 0 and remove Karpenter nodes to stop
# paying for EC2 spot capacity while keeping the EKS control plane running.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-sandbox}"
NODEGROUP_NAME="${NODEGROUP_NAME:-workers-spot-20260418183742674200000013}"
REGION="${AWS_REGION:-us-east-1}"

# Step 1: Remove Karpenter nodes by deleting the NodePool.
# Karpenter will drain and terminate all nodes it manages.
# EC2NodeClass stays — it has no running resources.
echo "Removing Karpenter NodePool (triggers node termination)..."
if kubectl get nodepool default 2>/dev/null; then
  kubectl delete nodepool default --wait=true --timeout=120s
  echo "Karpenter NodePool deleted. Nodes will terminate."
else
  echo "No Karpenter NodePool found, skipping."
fi

# Step 2: Scale managed node group to 0.
echo ""
echo "Scaling managed node group ${NODEGROUP_NAME} to desired=0..."
aws eks update-nodegroup-config \
  --region "${REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP_NAME}" \
  --scaling-config minSize=0,maxSize=5,desiredSize=0 \
  --output table

echo ""
echo "Estimated daily savings while scaled down: ~\$0.58 (EC2 spot) + EBS node volumes."
echo "Control plane continues to bill at ~\$2.40/day."
echo ""
echo "REMINDER: Run scale-up.sh to restore nodes and Karpenter NodePool."
