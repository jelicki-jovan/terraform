# modules

The project deliberately uses **both ways of working with modules**:

1. **Own, company-standard modules** (this folder): a platform team encodes its security and compliance
   rules in a module once, and every team that creates a bucket or a repository gets them by default,
   without having to know or remember them. Deviations are explicit (a named variable in the caller,
   visible in review). S3 and ECR were good option this time.
2. **Community modules** for the large building blocks: VPC, EKS, RDS, IAM roles for service accounts and
   Karpenter come from [`terraform-aws-modules`](https://github.com/terraform-aws-modules), pinned to a
   major version. They're widely used, maintained and tested; rebuilding them would add work, not value.
   The company standards still apply through the inputs (naming, encryption, logging, private subnets…),
   and a company could wrap them in its own thin modules the same way as S3/ECR.

Build where the standard is yours to define, reuse where others already do it well.

| Module | Used by | Enforced standard |
|---|---|---|
| [`s3`](s3/) | `management` (Terraform state), `environments/prod` (Loki logs) | private, public access fully blocked, encrypted, versioned, TLS-only |
| [`ecr`](ecr/) | `management` (one repository per app and environment) | immutable tags, scan on push, lifecycle policy |

## s3

```hcl
module "loki_bucket" {
  source = "../../modules/s3"

  environment = "prod"
  name        = "hw-loki-prod"

  versioning    = "Enabled"
  force_destroy = true
}
```

Defaults:
- **Public access blocked** (all four flags), objects owned by the bucket owner (ACLs disabled).
- **Encrypted** (SSE-S3; `sse_algorithm = "aws:kms"` + `kms_key_arn` for a customer-managed key).
- **Versioning** enabled.
- **Bucket policy denying any request without TLS**.

Options: `prevent_deletion` (bucket policy denying `s3:DeleteBucket`, used for the state bucket),
`force_destroy` (let `terraform destroy` empty the bucket, used for the Loki bucket), `public_read` /
`website` / `cors_rule` for static hosting (off by default, and public read refuses to work while the
public access block is on).

## ecr

```hcl
module "ecr_prod" {
  source = "../modules/ecr"

  for_each = toset(["backend", "frontend"])

  repository_name    = "hw-${each.key}-prod"
  keep_images_amount = 30
  force_delete       = true
}
```

Defaults:
- **Immutable tags**: a tag always points to the same image (deploys by commit SHA can't be overwritten).
- **Scan on push**.
- **Lifecycle policy**: untagged images expire after 1 day, keep the last `keep_images_amount_v` release
  images (`v*`) and the last `keep_images_amount` images overall (commit SHA tags); or a custom policy file.

Outputs: `repository_url`, `repository_arn`.
