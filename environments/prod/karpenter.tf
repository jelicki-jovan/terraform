module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.26"

  cluster_name = module.eks.cluster_name

  iam_role_name              = "hw-eks-karpenter-controller-prod"
  iam_role_use_name_prefix   = false
  iam_policy_name            = "hw-eks-karpenter-controller-prod"
  iam_policy_use_name_prefix = false

  queue_name       = "hw-eks-karpenter-prod"
  rule_name_prefix = "hw-karpenter-prod-"

  node_iam_role_name              = "hw-eks-karpenter-node-prod"
  node_iam_role_use_name_prefix   = false
  node_iam_role_attach_cni_policy = false
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.14.1"

  depends_on = [module.eks]
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.14.1"

  skip_crds = true

  values = [
    yamlencode({
      replicas = 2
      nodeSelector = {
        "kubernetes.io/os" = "linux"
        "workload-type"    = "system"
      }
      serviceAccount = {
        name = module.karpenter.service_account
      }
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      controller = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }
      }
    })
  ]

  depends_on = [module.eks, helm_release.karpenter_crd]
}
