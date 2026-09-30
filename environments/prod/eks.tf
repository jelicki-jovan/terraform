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
      addon_version            = "v1.23.1-eksbuild.1"
      before_compute           = true
      service_account_role_arn = module.vpc_cni_irsa.arn
      configuration_values = jsonencode({
        # Enforce Kubernetes NetworkPolicies (network policy agent in aws-node); off by default
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      addon_version = "v1.36.0-eksbuild.25"
    }
    eks-pod-identity-agent = {
      addon_version  = "v1.4.0-eksbuild.2"
      before_compute = true
    }
    coredns = {
      addon_version = "v1.14.6-eksbuild.4"
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
      addon_version            = "v1.66.0-eksbuild.1"
      service_account_role_arn = module.ebs_csi_irsa.arn
      configuration_values = jsonencode({
        controller = {
          nodeSelector = {
            "workload-type" = "system"
          }
          # Every volume created by the driver gets this tag: the DLM policy snapshots them daily
          extraVolumeTags = {
            backup = "daily"
          }
        }
        node = {
          tolerateAllTaints = true
        }
      })
    }
    metrics-server = {
      addon_version = "v0.9.0-eksbuild.11"
      configuration_values = jsonencode({
        nodeSelector = {
          "workload-type" = "system"
        }
        podDisruptionBudget = {
          enabled        = true
          maxUnavailable = 1
        }
      })
    }
  }

  eks_managed_node_groups = {
    system = {
      name     = "system"
      ami_type = "AL2023_x86_64_STANDARD"
      # Pinned AMI release (same as Karpenter's EC2NodeClass al2023@v20260923); bump deliberately to roll nodes
      use_latest_ami_release_version = false
      ami_release_version            = "1.36.4-20260923"
      capacity_type                  = "ON_DEMAND"
      instance_types                 = ["t3.medium"]

      # 4 nodes: headroom for monitoring (Prometheus, Loki, Grafana) next to the platform add-ons
      min_size     = 4
      max_size     = 5
      desired_size = 4

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

### Backups of the cluster's persistent volumes: daily EBS snapshots with Data Lifecycle Manager (AWS
### Backup is denied by the SCP). Targets every volume tagged backup=daily, which the EBS CSI driver adds
### to ALL volumes it creates (extraVolumeTags in the add-on config above): any PVC is covered
### automatically (today Prometheus, Loki). RDS has its own automated backups (rds.tf).
resource "aws_iam_role" "dlm" {
  name = "hw-dlm-prod"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dlm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "ebs_daily" {
  # Only letters, digits, spaces, _ and - allowed
  description        = "hw-ebs-daily-prod - daily snapshots of volumes tagged backup daily - keep 7"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      backup = "daily"
    }

    schedule {
      name = "daily"

      # After the RDS backup window (03:00-04:00 UTC)
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["04:00"]
      }

      retain_rule {
        count = 7
      }

      # Volume tags (kubernetes.io/created-for/pvc/name, ...) show which PVC a snapshot belongs to
      copy_tags = true

      tags_to_add = {
        SnapshotCreator = "dlm"
      }
    }
  }

  tags = {
    Name = "hw-ebs-daily-prod"
  }
}

module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name            = "hw-eks-aws-lb-controller-prod"
  use_name_prefix = false
  policy_name     = "hw-eks-aws-lb-controller-prod"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

### External Secrets: one IAM role per namespace (the ESO controller itself has no AWS access).
### A namespace's SecretStore logs in as its own "external-secrets" service account and can read
### only secrets named "<namespace>/*" (+ that namespace's RDS secret).
module "eso_namespace_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  ### namespace iteration
  for_each = {
    prod = [module.rds.db_instance_master_user_secret_arn]
  }

  name            = "hw-eks-eso-ns-${each.key}"
  use_name_prefix = false
  policy_name     = "hw-eks-eso-ns-${each.key}"

  attach_external_secrets_policy = true
  external_secrets_secrets_manager_arns = concat(
    ["arn:aws:secretsmanager:us-east-1:003636669641:secret:${each.key}/*"],
    each.value,
  )

  oidc_providers = {
    eks_prod = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${each.key}:external-secrets"]
    }
  }
}

### Platform on the cluster: Karpenter + Argo CD bootstrap (./platform). Installed after the cluster and
### its system node group exist; the cluster never depends on it.
module "platform" {
  source = "./platform"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint

  depends_on = [module.eks]
}
