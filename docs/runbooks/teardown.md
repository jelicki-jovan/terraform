# Runbook: tear everything down

A plain `terraform destroy` isn't enough: some AWS resources are created **by controllers inside the
cluster**, not by Terraform, and would be left behind (and keep costing money) once the cluster is gone:

| Created by | Resource | Removed by |
|---|---|---|
| AWS Load Balancer Controller (from the frontend Ingress) | ALB, target group, its security groups | deleting the Ingress while the controller still runs |
| Karpenter (from the NodePools) | EC2 app nodes, their instance profiles | deleting the NodePools / EC2NodeClass while Karpenter still runs |
| EBS CSI driver (from PersistentVolumeClaims) | EBS volumes (Prometheus, Loki) | deleting the PVCs while the driver still runs |

So: first remove those through Kubernetes, **then** destroy with Terraform. Order: prod and dev →
management last.

**Dev** is torn down the same way as prod: steps 1-3 against the dev cluster (`hw-eks-dev`) and
`environments/dev` (its database has no deletion protection and takes no final snapshot, so step 3's
protection change and step 4's backups don't apply).

## Before you start

- AWS CLI logged in to the account, with an IAM identity that has **cluster admin** access to
  `hw-eks-prod` (an EKS access entry, see `environments/prod/eks.tf`), and `kubectl` installed.
- Connect `kubectl` to the cluster (adds it to your kubeconfig and makes it the current context):

  ```bash
  aws eks update-kubeconfig --name hw-eks-prod --region us-east-1
  kubectl config current-context   # must end with cluster/hw-eks-prod
  kubectl get nodes                 # access works
  ```

## 1. Stop Argo CD

With auto-sync and self-heal, Argo CD would re-create from Git everything deleted in the next step.
Deleting Applications doesn't reliably stop that (a parent app can re-create a child before it's deleted
itself). Stopping Argo CD's **application controller** does: with no controller running, nothing is synced
or healed anymore. The running workloads stay as they are; Argo CD itself is removed by `terraform destroy`
later.

```bash
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0
kubectl -n argocd get pods   # no argocd-application-controller pod left
```

## 2. Remove what the controllers created

```bash
# ALB: the Load Balancer Controller deletes it when the Ingress goes
kubectl -n prod delete ingress --all
aws elbv2 describe-load-balancers --region us-east-1 --names hw-alb-prod   # repeat until "not found"

# EBS volumes: delete the monitoring workloads, then their PVCs (reclaim policy Delete → volumes deleted)
kubectl -n monitoring delete prometheus,alertmanager --all
kubectl -n monitoring delete statefulset --all
kubectl -n monitoring delete pvc --all
kubectl get pv                                                             # repeat until empty

# App nodes: Karpenter drains and terminates them when their NodePools go
kubectl delete nodepools --all
kubectl get nodeclaims                                                     # repeat until empty
kubectl delete ec2nodeclasses --all
```

## 3. Destroy the prod environment

The database has deletion protection on purpose. Turn it off in `environments/prod/rds.tf`
(`deletion_protection = false`) and apply, then destroy:

```bash
cd environments/prod
terraform apply        # only the deletion_protection change
terraform destroy
```

Terraform removes Argo CD and Karpenter first (the `platform` module depends on the cluster), then the
cluster, RDS (a final snapshot `hw-rds-prod-final-*` is taken), the VPC, IAM roles, buckets and alarms.

## 4. Left behind on purpose (backups)

These survive the destroy so data isn't lost by accident. Delete them when they're really not needed:

```bash
# RDS: final snapshot + automated backups (kept until they expire after 7 days)
aws rds describe-db-snapshots --region us-east-1 --snapshot-type manual \
  --query 'DBSnapshots[?starts_with(DBSnapshotIdentifier,`hw-rds-prod-final`)].DBSnapshotIdentifier'
aws rds delete-db-snapshot --region us-east-1 --db-snapshot-identifier <id>
aws rds describe-db-instance-automated-backups --region us-east-1 \
  --query 'DBInstanceAutomatedBackups[].DbiResourceId'
aws rds delete-db-instance-automated-backup --region us-east-1 --dbi-resource-id <id>

# EBS snapshots made by the daily DLM policy
aws ec2 describe-snapshots --region us-east-1 --owner-ids self \
  --filters Name=tag:SnapshotCreator,Values=dlm --query 'Snapshots[].SnapshotId'
aws ec2 delete-snapshot --region us-east-1 --snapshot-id <id>
```

KMS keys (EKS secrets encryption) aren't deleted immediately: AWS schedules them for deletion after a
waiting period.

## 5. Destroy management (only when nothing else is left)

The state bucket holds the state of every stack (its own included) and has a policy that denies deleting
it. To remove it:

1. In `management/terraform.tf`, comment out the `backend "s3"` block and run
   `terraform init -migrate-state`: the state moves to a local file.
2. In `management/s3.tf`, set `prevent_deletion = false` and `force_destroy = true` (the bucket is versioned
   and not empty), then `terraform apply`.
3. `terraform destroy`: removes the ECR repositories (with their images), the GitHub OIDC role and
   provider, the Spot service-linked role and the state bucket.

## Check

```bash
aws ec2 describe-instances --region us-east-1 --filters Name=tag:karpenter.sh/nodepool,Values=* \
  Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-volumes --region us-east-1 --filters Name=tag:backup,Values=daily --query 'Volumes[].VolumeId'
```

All three should return empty lists.
