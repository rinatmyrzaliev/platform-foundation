#!/usr/bin/env bash
# Print the initial ArgoCD admin password. ArgoCD stores it in a Secret that
# is auto-generated on first install; rotate it (or delete the Secret) as soon
# as you've logged in the first time.
set -euo pipefail

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
