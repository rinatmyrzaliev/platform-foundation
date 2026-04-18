# A gp3 default StorageClass so Prometheus (and any other PVC consumer) lands
# on gp3 instead of the legacy gp2 class the EBS CSI addon ships with.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.10"
  namespace        = "argocd"
  create_namespace = true

  # ADR-004: ClusterIP only — access via `kubectl port-forward`.
  # Avoids ~$18/mo ALB and keeps the ArgoCD UI off the public internet.
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [module.eks]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.2"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  namespace        = "ingress-nginx"
  create_namespace = true

  # ADR-003: NodePort instead of a LoadBalancer Service. Avoids the AWS Load
  # Balancer Controller + ALB (~$18/mo base) in the sandbox.
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  depends_on = [module.eks]
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.1.1"
  namespace        = "monitoring"
  create_namespace = true

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention = "7d"
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "10Gi"
                }
              }
            }
          }
        }
      }
    }
    grafana = {
      service = {
        type = "ClusterIP"
      }
    }
    alertmanager = {
      enabled = true
    }
  })]

  depends_on = [
    module.eks,
    kubernetes_storage_class_v1.gp3,
  ]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.5"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}
