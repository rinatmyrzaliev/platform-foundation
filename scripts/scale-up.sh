#!/usr/bin/env bash
# Scale the managed node group back to 2 nodes and wait until kubelet reports
# Ready on all of them. Pair with scale-down.sh for the nightly off/on cycle.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-sandbox}"
NODEGROUP_NAME="${NODEGROUP_NAME:-workers-spot}"
REGION="${AWS_REGION:-us-east-1}"
DESIRED="${DESIRED:-2}"

echo "Scaling node group ${NODEGROUP_NAME} to desired=${DESIRED}..."

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

echo ""
kubectl get nodes -o wide
