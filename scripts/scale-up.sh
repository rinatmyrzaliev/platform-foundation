#!/usr/bin/env bash
# Scale the managed node group back up and restore the Karpenter NodePool.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-sandbox}"
NODEGROUP_NAME="${NODEGROUP_NAME:-workers-spot-20260418183742674200000013}"
REGION="${AWS_REGION:-us-east-1}"
DESIRED="${DESIRED:-3}"

# Step 1: Scale managed node group back up.
echo "Scaling managed node group ${NODEGROUP_NAME} to desired=${DESIRED}..."
aws eks update-nodegroup-config \
  --region "${REGION}" \
  --cluster-name "${CLUSTER_NAME}" \
  --nodegroup-name "${NODEGROUP_NAME}" \
  --scaling-config "minSize=0,maxSize=5,desiredSize=${DESIRED}" \
  --output table

echo ""
echo "Refreshing kubeconfig..."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

echo ""
echo "Waiting for nodes to reach Ready (timeout 10m)..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m

# Step 2: Restore Karpenter NodePool if it doesn't exist.
echo ""
echo "Checking Karpenter NodePool..."
if kubectl get nodepool default 2>/dev/null; then
  echo "Karpenter NodePool already exists."
else
  NODEPOOL_FILE="${NODEPOOL_FILE:-$(dirname "$0")/../../platform-autoscaling/manifests/karpenter/nodepool.yaml}"
  if [ -f "$NODEPOOL_FILE" ]; then
    echo "Restoring Karpenter NodePool from ${NODEPOOL_FILE}..."
    kubectl apply -f "$NODEPOOL_FILE"
  else
    echo "WARNING: NodePool manifest not found at ${NODEPOOL_FILE}"
    echo "Manually apply your NodePool: kubectl apply -f <path-to-nodepool.yaml>"
  fi
fi

echo ""
kubectl get nodes -o wide
echo ""
kubectl get nodepool 2>/dev/null || echo "No Karpenter NodePool found."
