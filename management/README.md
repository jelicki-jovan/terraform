# management

Account-level resources shared by all environments. Applied first, rarely changed. State:
`s3://terraform-backend-home-work/management/terraform.tfstate`.

| File | What | Why here |
|---|---|---|
| `s3.tf` | Terraform state bucket `terraform-backend-home-work` | Every stack (this one included) keeps its state there |
| `ecr.tf` | ECR repositories `hw-backend-prod`, `hw-frontend-prod` | Images are built once by CI and pulled by the cluster |
| `github-oidc.tf` | GitHub OIDC provider + role `hw-github-actions-ecr` | CI pushes images without any stored AWS keys |
| `spot.tf` | EC2 Spot service-linked role | Needed once per account before any spot instance can start |

## State bucket

- Private, encrypted, **versioned** (every state version can be restored), TLS-only, and a bucket policy
  that **denies deleting the bucket** (to delete it, that statement has to be removed first, on purpose).
- Locking with S3 native lock files (`use_lockfile`), no DynamoDB table needed.
- **Bootstrap (chicken-and-egg)**: the bucket that stores the state is created by the stack that uses it.
  1. Comment out the `backend "s3"` block in `terraform.tf`, `terraform init && terraform apply` (local state).
  2. Restore the block, `terraform init -migrate-state`: the local state is copied into the new bucket.

  Trade-off: no separate bootstrap stack, but a broken management apply could affect the state bucket. In a
  larger organisation it would live in its own stack or account.

## ECR

- One set of repositories **per environment** (`hw-<app>-prod`), created with `for_each` from the own
  [ECR module](../modules/README.md).
- **Immutable tags** (a tag like `c287398` always means the same image), **scan on push** (Amazon Inspector
  findings in the console, on top of the Trivy gate in CI).
- Lifecycle: untagged images removed after 1 day, keep the last 30 commit tags and the last 5 `v*` releases.
- `force_delete = true`: `terraform destroy` works with images inside (a demo setting; production: `false`).
- Trade-off of per-environment repositories: promoting from dev to prod means copying the tested image
  (by digest) instead of deploying the same tag; in return prod repositories can be locked down to prod CI.

## GitHub OIDC

- CI gets short-lived AWS credentials from GitHub's OIDC token: **no AWS keys stored in GitHub**.
- The role trusts only the app repository's **`main` branch**, matched by GitHub's **immutable owner and
  repository IDs** (`repo:jelicki-jovan@333439828/Incode-conduit-realworld-example-app@1385920809:ref:refs/heads/main`):
  pull requests, forks and other branches can't assume it, and a deleted repository re-created under the
  same name by someone else wouldn't match either.
- Permissions: push/pull on the two prod repositories only (+ `ecr:GetAuthorizationToken`, which has no
  resource-level permissions). The role ARN is not a secret: the trust policy protects it.

## Spot service-linked role

EC2 creates it automatically on the first spot request, but only if the caller may create IAM roles.
Karpenter's controller correctly can't, so the first spot launch failed; the role is created here once.

## Outputs

| Output | Used for |
|---|---|
| `ecr_prod_urls` | Image names in `k8s-envs` |
| `github_actions_ecr_role_arn` | App repo's GitHub Actions configuration |

## Apply

```bash
cd management
terraform init
terraform plan
terraform apply
```

Everything else ([`environments/prod`](../environments/prod/README.md)) expects this stack to exist.
