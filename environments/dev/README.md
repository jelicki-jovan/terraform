# environments/dev

The dev environment: its own VPC, EKS cluster and database, separate from prod. It exists to **separate the
environments** and for the **release flow**: every change is deployed here first and must pass the
performance test before the same image is promoted to prod. State:
`s3://terraform-backend-home-work/dev/terraform.tfstate`.

Same files and structure as [`environments/prod`](../prod/README.md) (including `platform/` for Karpenter and
Argo CD); the differences are written directly in the code, so dev can be read on its own:

| | prod | dev |
|---|---|---|
| VPC | `10.1.0.0/16`, one NAT gateway per AZ | `10.2.0.0/16`, **one NAT gateway** for all AZs |
| System node group | 4× t3.medium | **2×** t3.medium |
| App nodes (Karpenter) | spot + on-demand | **spot only** |
| RDS | `db.t3.small`, Multi-AZ, deletion protection, final snapshot, 7-day backups | `db.t4g.micro`, **single-AZ**, no deletion protection or final snapshot, 1-day backups |
| Monitoring, alerting, EBS snapshots | Prometheus/Grafana/Loki storage and roles, SNS alerts, CloudWatch alarms, DLM | **none** |
| Apps (in `k8s-envs`) | backend 3-6 replicas, frontend 3 | 1 replica each |
| The same | EKS version and add-ons, IAM database auth for the app, IRSA / Pod Identity, secrets `dev/*` via External Secrets, Pod Security, the images (same digest as prod) | |

## Apply

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

- Needs [`management`](../../management/README.md) (state bucket, ECR repositories `hw-*-dev`).
- Argo CD in the dev cluster syncs [`k8s-envs/argocd/dev`](https://github.com/jelicki-jovan/k8s-envs) and
  deploys the apps from `environments/dev/`.
- Access: `aws eks update-kubeconfig --name hw-eks-dev --region us-east-1` (a separate kubeconfig file or
  context keeps it apart from prod).
- Tear down the same way as prod ([runbook](../../docs/runbooks/teardown.md)).
