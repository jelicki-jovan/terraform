### EC2 Spot service-linked role: required before any Spot instance can be launched in the account.
### EC2 normally creates it on the first Spot request, but Karpenter's controller is (correctly) not
### allowed to create IAM roles, so it's created here once. AWS-managed policy, assumable only by EC2 Spot.
resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Allows EC2 to launch Spot instances (Karpenter spot NodePool)"
}
