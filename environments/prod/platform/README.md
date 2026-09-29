# platform

Local module (`source = "./platform"`, called from `../eks.tf`): what runs **on** the EKS cluster and
bootstraps it. Depends only on the cluster (one-way: EKS never depends on this).

- `karpenter.tf`: Karpenter AWS side (controller role via Pod Identity, node role, SQS interruption queue,
  EventBridge rules) + Helm releases (CRDs, controller on the system nodes).
- `argocd.tf`: Argo CD + the root Application syncing `k8s-envs/argocd/prod` (GitOps takes over from here).

Inputs: `cluster_name`, `cluster_endpoint`. Uses the root's `aws` and `helm` providers.
