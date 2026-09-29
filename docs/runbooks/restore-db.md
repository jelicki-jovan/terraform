# Runbook: restore the database

Two procedures: a regular **restore test** (no downtime) and a **production restore** after data loss
(maintenance window).

## Before you start

- AWS CLI logged in to the account, with an IAM identity that has **cluster admin** access to
  `hw-eks-prod` (an EKS access entry, see `environments/prod/eks.tf`), and `kubectl` installed.
- Connect `kubectl` to the cluster (adds it to your kubeconfig and makes it the current context):

  ```bash
  aws eks update-kubeconfig --name hw-eks-prod --region us-east-1
  kubectl config current-context   # must end with cluster/hw-eks-prod
  kubectl get nodes                 # access works
  ```

## What can be restored

- RDS `hw-rds-prod` (PostgreSQL 17, Multi-AZ, encrypted): automated backups, **7 days**, daily snapshot in the
  03:00-04:00 UTC window + transaction logs (WAL) uploaded ~every 5 min → **point-in-time restore (PITR)** to
  any second between `EarliestTime` and `LatestRestorableTime` (~5 min behind now).
- `delete_automated_backups = false`: PITR backups survive an accidental instance delete until they expire;
  final snapshot `hw-rds-prod-final-*` on delete.
- Stored in AWS-managed S3, in the same account and region (us-east-1).
- A restore **always creates a new instance** (RDS never restores "in place").

Useful lookups:
```bash
# restore window
aws rds describe-db-instance-automated-backups --region us-east-1 --db-instance-identifier hw-rds-prod \
  --query 'DBInstanceAutomatedBackups[0].RestoreWindow'
# network/params the restored instance needs (subnet group, security group, parameter group = force_ssl)
aws rds describe-db-instances --region us-east-1 --db-instance-identifier hw-rds-prod \
  --query 'DBInstances[0].{subnetGroup:DBSubnetGroup.DBSubnetGroupName,sg:VpcSecurityGroups[0].VpcSecurityGroupId,pg:DBParameterGroups[0].DBParameterGroupName,latest:LatestRestorableTime}'
```

## Two different procedures

| | Restore **test** | **Production** restore (real incident) |
|---|---|---|
| Why | prove backups work, measure restore time (RTO) | recover from data loss/corruption |
| Target | new, separate instance, deleted afterwards | new instance that becomes production |
| Production impact | **none**, no downtime, users notice nothing | **downtime**: maintenance window |
| How often | regularly (e.g. monthly; could be automated) | only when needed |

"A backup nobody has restored is only a hope": the test is what makes the backups count.

## A. Restore test (no downtime)

Idea: create data, delete it on purpose, restore to a point **between** create and delete, prove the data is
back in the restored copy (not in prod). Record times → real RTO.

0. **Marker data** (in the app): log in, create article `restore-test-1`, note T1
   (`date -u +%Y-%m-%dT%H:%M:%SZ`); wait ~2 min; delete the article; note T2.
   Wait **≥ 5 min after T2** (restore point must be older than `LatestRestorableTime`).
1. **Restore** to T1 + ~1 min into a new single-AZ instance (cheaper; Multi-AZ isn't what's being tested):
   ```bash
   aws rds restore-db-instance-to-point-in-time --region us-east-1 \
     --source-db-instance-identifier hw-rds-prod \
     --target-db-instance-identifier hw-rds-restore-test \
     --restore-time <T1+1min, e.g. 2026-09-29T09:31:00Z> \
     --db-instance-class db.t4g.micro --no-multi-az \
     --db-subnet-group-name prod-vpc \
     --vpc-security-group-ids <RDS security group id, from the lookup above> \
     --db-parameter-group-name hw-rds-prod \
     --no-publicly-accessible \
     --manage-master-user-password \
     --enable-iam-database-authentication \
     --tags Key=purpose,Value=restore-test Key=Project,Value=home-work
   ```
   - `--manage-master-user-password`: RDS creates a **new** managed secret for the copy (the prod secret
     stays linked to prod).
   - Same SG → reachable only from EKS nodes; same parameter group → SSL still enforced.
2. **Wait + time it** (start time = when the command ran):
   ```bash
   time aws rds wait db-instance-available --region us-east-1 --db-instance-identifier hw-rds-restore-test
   ```
   (the waiter gives up after ~30 min; just run it again if needed)
3. **Connect** (RDS is private → temporary psql pod inside the cluster, `default` namespace because `prod`
   enforces the restricted Pod Security profile and the postgres image runs as root):
   ```bash
   HOST=$(aws rds describe-db-instances --region us-east-1 --db-instance-identifier hw-rds-restore-test \
     --query 'DBInstances[0].Endpoint.Address' --output text)
   SECRET=$(aws rds describe-db-instances --region us-east-1 --db-instance-identifier hw-rds-restore-test \
     --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text)
   PASS=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id "$SECRET" \
     --query SecretString --output text | python3 -c 'import json,sys;print(json.load(sys.stdin)["password"])')
   kubectl run psql-restore-test -n default --rm -it --restart=Never --image=postgres:17-alpine \
     --env="PGPASSWORD=$PASS" -- \
     psql "host=$HOST dbname=home_work user=home_work_admin sslmode=require"
   ```
4. **Verify**:
   ```sql
   SELECT id, title, "createdAt" FROM "Articles" WHERE title = 'restore-test-1';  -- 1 row (deleted in prod)
   SELECT (SELECT count(*) FROM "Users") users, (SELECT count(*) FROM "Articles") articles,
          (SELECT count(*) FROM "Comments") comments;
   ```
   Same counts on prod (same pod, prod host) → only the marker article differs.
5. **Clean up** (the copy's managed secret is deleted with it):
   ```bash
   aws rds delete-db-instance --region us-east-1 --db-instance-identifier hw-rds-restore-test \
     --skip-final-snapshot --delete-automated-backups
   ```
6. **Record**: restore point, command start, available time → RTO; RPO = how far behind "now" the latest
   restorable point was (~5 min).

## B. Production restore (real incident, maintenance window)

Order matters: **stop writes first**, otherwise new data keeps landing in the broken database and is lost
after the switch.

1. **Announce + maintenance mode**:
   - Tell users (status page / banner / email) that the app is down for maintenance.
   - Show a maintenance page: e.g. frontend on 1 replica serving a static "we're down for maintenance"
     page (or an ALB fixed-response 503 rule via the Ingress annotation `alb.ingress.kubernetes.io/actions`).
   - **Stop the backend** so nothing writes to the DB: with GitOps a plain `kubectl scale --replicas=0`
     gets undone (ArgoCD selfHeal + HPA min 3) → first **disable auto-sync** for `hw-backend-prod`
     (or commit the change to `k8s-envs`), then scale to 0 / remove the HPA.
2. **Pick the restore point**: last good moment before the incident (from logs in Loki/CloudWatch, the
   time of the bad deploy/migration, …). Everything written after it is lost (tell users).
3. **Restore** into a new instance with **production settings** (Multi-AZ, same class/params/SG/subnet
   group, IAM authentication enabled), same command as the test but e.g.
   `--target-db-instance-identifier hw-rds-prod-restored --multi-az`. The app's database user
   (`app_user`, with its `rds_iam` grant) is part of the restored data.
4. **Verify the data** on the new instance (psql pod as in the test) before switching.
5. **Switch the app to it**, two options:
   - **Rename** (endpoint hostname follows the identifier, so the app config stays the same):
     `hw-rds-prod` → `hw-rds-prod-old`, then `hw-rds-prod-restored` → `hw-rds-prod`
     (`aws rds modify-db-instance --new-db-instance-identifier … --apply-immediately`).
   - **Or** point the backend at the new endpoint (ConfigMap DB host in `k8s-envs`).
   - Either way the **master credentials change** (new RDS-managed secret) → update the secret name the
     migration Job's ExternalSecret reads, and let ESO refresh the Kubernetes Secret.
   - Either way the **backend can't log in yet**: its IAM policy allows `rds-db:connect` only on the old
     instance's **resource ID** (`dbuser:db-XXXX/app_user`). The restored instance has a new resource ID,
     also after a rename (resource IDs never change). Fixed in the next step.
6. **Bring Terraform back in line**: the state still points at the old instance → `terraform state rm` the
   old instance + `terraform import` the new one. `terraform plan` must show **no destroy/replace** of the
   database, and an in-place update of the backend's IAM policy to the new resource ID (it's built from
   the instance's resource ID) → `terraform apply`. Keep `deletion_protection` on.
7. **Start the backend** only after step 6 (re-enable Argo CD auto-sync), check health, logs, a login +
   article read. A `PAM authentication failed for user "app_user"` in the backend logs means the IAM
   policy still points at the old instance.
8. **End maintenance**, tell users; keep the old instance for a few days (forensics), then delete it
   (disable deletion protection first).
9. **Post-mortem**: cause, data loss window, how long it took, what to improve.

Production improvements: restore drill automated (scheduled job restoring + checking + deleting,
alert on failure), longer retention (14-35 days), cross-account/region snapshot copies (AWS Backup vault
with lock), a maintenance-mode switch prepared in advance (not improvised during the incident).
