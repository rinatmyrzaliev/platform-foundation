#!/usr/bin/env bash
# Scale the managed node group to 0 nodes to stop paying for EC2 spot capacity
# while keeping the EKS control plane (~$0.10/hr) running. The control plane
# can't be scaled; destroy the cluster if you want it fully off.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-sandbox}"
NODEGROUP_NAME="${NODEGROUP_NAME:-workers-spot}"
REGION="${AWS_REGION:-us-east-1}"

echo "Scaling node group ${NODEGROUP_NAME} in cluster ${CLUSTER_NAME} to desired=0..."

aws eks update-nodegroup-config \
  --region "${REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP_NAME}" \
  --scaling-config minSize=0,maxSize=5,desiredSize=0 \
  --output table

# Rough spot pricing for 2x t3.medium in us-east-1 is ~$0.012/hr per node.
# Scaling to 0 therefore saves ~$0.024/hr ≈ $0.58/day on EC2.
# (EBS for node root volumes also stops accruing; Prometheus PVC still bills.)
echo ""
echo "Estimated daily savings while scaled down: ~\$0.58 (EC2 spot) + EBS node volumes."
echo "Control plane continues to bill at ~\$2.40/day."
