# Inputs from the EKS cluster (eks.tf). Everything else is prod-specific and set inline.
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint (Karpenter's settings.clusterEndpoint)"
  type        = string
}
