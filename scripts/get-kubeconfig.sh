#!/usr/bin/env bash
# Merge the sandbox cluster's kubeconfig into ~/.kube/config and set it as the
# current context. Re-run any time aws credentials change.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-platform-sandbox}"
REGION="${AWS_REGION:-us-east-1}"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"
kubectl config current-context
