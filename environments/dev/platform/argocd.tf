resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.9.2"

  values = [
    yamlencode({
      global = {
        nodeSelector = {
          "workload-type" = "system"
        }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }]
      }
      dex = {
        enabled = false
      }
      notifications = {
        enabled = false
      }
      configs = {
        cm = {
          # Poll Git every 30 s (default 120 s + up to 60 s jitter): deploys land in <= ~30 s
          # without a webhook (ArgoCD isn't reachable from GitHub: no domain)
          "timeout.reconciliation"        = "30s"
          "timeout.reconciliation.jitter" = "0s"
        }
      }
    })
  ]
}

### Root application: syncs the top-level Application manifests in k8s-envs/argocd/dev
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root-app"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.5"

  values = [
    yamlencode({
      applications = {
        dev = {
          namespace = "argocd"
          project   = "default"
          source = {
            repoURL        = "https://github.com/jelicki-jovan/k8s-envs.git"
            targetRevision = "main"
            path           = "argocd/dev"
            directory = {
              recurse = false
            }
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}
