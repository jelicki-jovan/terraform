module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = "hw-eks-prod"
  kubernetes_version = "1.36"

  iam_role_name                       = "hw-eks-cluster-prod"
  iam_role_use_name_prefix            = false
  encryption_policy_name              = "hw-eks-cluster-encryption-prod"
  encryption_policy_use_name_prefix   = false
  security_group_name                 = "hw-eks-cluster-prod"
  security_group_use_name_prefix      = false
  node_security_group_name            = "hw-eks-node-prod"
  node_security_group_use_name_prefix = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["0.0.0.0/0"]

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    jovan_admin = {
      principal_arn = "arn:aws:iam::003636669641:user/jovan-admin"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  enable_irsa = true

  node_security_group_tags = {
    "karpenter.sh/discovery" = "hw-eks-prod"
  }

  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 30

  addons = {
    vpc-cni = {
      before_compute           = true
      service_account_role_arn = module.vpc_cni_irsa.arn
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    coredns = {
      configuration_values = jsonencode({
        replicaCount = 3
        nodeSelector = {
          "workload-type" = "system"
        }
        podDisruptionBudget = {
          enabled        = true
          maxUnavailable = 1
        }
        topologySpreadConstraints = [{
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "ScheduleAnyway"
          labelSelector = {
            matchLabels = {
              "k8s-app" = "kube-dns"
            }
          }
        }]
      })
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.arn
      configuration_values = jsonencode({
        controller = {
          nodeSelector = {
            "workload-type" = "system"
          }
        }
        node = {
          tolerateAllTaints = true
        }
      })
    }
  }

  eks_managed_node_groups = {
    system = {
      name           = "system"
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.medium"]

      min_size     = 3
      max_size     = 4
      desired_size = 3

      cloudinit_pre_nodeadm = [{
        content_type = "application/node.eks.aws"
        content      = <<-EOT
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                maxPods: 110
        EOT
      }]

      iam_role_name              = "hw-eks-node-system-prod"
      iam_role_use_name_prefix   = false
      iam_role_attach_cni_policy = false
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      labels = {
        "workload-type" = "system"
      }

      taints = {
        critical_addons_only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-vpc-cni-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-vpc-cni-prod"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-ebs-csi-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-ebs-csi-prod"

  attach_ebs_csi_policy = true

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
