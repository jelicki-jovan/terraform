# Known gaps

What's missing or simplified, why, and what I'd do in production. Grouped by cause:

1. [Limits of the provided AWS account](#1-limits-of-the-provided-aws-account): things the account doesn't allow
2. [Security and access](#2-security-and-access)
3. [Delivery and infrastructure as code](#3-delivery-and-infrastructure-as-code)
4. [Kubernetes and networking](#4-kubernetes-and-networking)
5. [Data and backups](#5-data-and-backups)
6. [Observability](#6-observability)

## 1. Limits of the provided AWS account

The account is a member of an AWS Organization managed with Control Tower and restricted by SCPs. I
checked each limit with real read-only calls (the IAM policy simulator alone was misleading: it doesn't
evaluate the SCPs' conditions).

| Limit | Effect on the design | With the limit lifted |
|---|---|---|
| **Only `us-east-1`** | Everything runs there; no second region for backups or DR | Backup copies / DR in a second region |
| **EC2 only t2/t3/t3a up to `medium`** | 4 GB nodes: system node group needs 4 nodes; VPC CNI prefix delegation to fit more than 17 pods per node; Karpenter limited to t3/t3a small + medium (t2 can't do prefix delegation) | Larger, fewer system nodes; a wide instance mix for Karpenter (better spot availability and consolidation) |
| **AWS Backup denied** | Backups with RDS automated backups + Data Lifecycle Manager (EBS) + S3 versioning | One central backup plan and vault, with a vault lock and cross-account copies |
| **AWS Pricing API denied** | Karpenter logs price-lookup errors every few seconds; it works with its built-in price list. I left the noise rather than switching to Karpenter's isolated-VPC mode, which would break the clean `terraform destroy` | Allow `pricing:GetProducts` |
| **Budgets and Cost Explorer denied** | No budget alert in code; costs kept low with small instances and teardown after the demo | A monthly budget with alerts, per-environment cost tags |
| **No IAM Identity Center** (managed by the organisation) | I work as an IAM user with MFA and short-lived `aws login` credentials; Amazon Managed Grafana isn't possible (needs Identity Center), so Grafana is self-hosted | SSO permission sets for people; Managed Grafana/Prometheus as an option |

## 2. Security and access

- **Public EKS API endpoint, open to `0.0.0.0/0`.** I have no static IP or VPN to allowlist, and a home IP
  in a public repo would leak and change anyway. Still protected by IAM authentication, one access entry and
  audit logs; nodes use the private endpoint. *Production:* private endpoint only, reached through a VPN or
  an SSM bastion (or an allowlist of static office/VPN IPs).
- **Only my IAM user has cluster access.** Someone else gets `Unauthorized` (and a Terraform apply by them
  fails on the Helm releases). *Production:* SSO roles (platform admin / developer / read-only) mapped to
  access entries; access managed by SSO assignments, not per person in Terraform.
- **No HTTPS.** No domain, so no ACM certificate: users → ALB is plain HTTP. *Production:* Route 53 + ACM,
  HTTPS listener with an HTTP → HTTPS redirect.
- **Traffic inside the VPC isn't encrypted** (ALB → pods, pod → pod). Encrypted today: backend → RDS
  (verified TLS), all AWS/Kubernetes APIs, secrets at rest (KMS). *Production:* a service mesh with
  automatic mTLS (Linkerd/Istio), or end-to-end TLS from the ALB.
- **No NetworkPolicies.** Enforcement is enabled in the VPC CNI, but no policies are written: the backend
  isn't public (no Ingress), yet any pod in the cluster could reach it. *Next step:* default-deny per
  namespace, backend reachable only from the frontend and monitoring.
- **Public repositories show non-secret identifiers** (account ID, role ARNs, RDS hostname in `k8s-envs`).
  None of them grants access, but they make enumeration and targeted phishing easier. *Production:* private
  GitOps repository. (No secret values are committed to any repository: credentials are created at runtime
  or live in Secrets Manager; the only CI secret, the `k8s-envs` deploy key, is an encrypted GitHub Actions
  secret, not part of the code or its history.)
- **Argo CD and Grafana use local admin logins**, reachable only via `kubectl port-forward`. *Production:*
  SSO (OIDC) and an Ingress behind it; Grafana's admin password in Secrets Manager.
- **The migration Job still uses the RDS master user** (the app itself uses IAM auth). DDL needs the table
  owner, and creating the app's DB user needs admin rights. *Production:* a separate `migrator` user that
  owns the schema and logs in with IAM auth too (no password anywhere, the master becomes break-glass
  only), and DB users/grants created by a separate platform step, not by the app's own migrations.
- **SNS alert topics aren't KMS-encrypted.** CloudWatch can't publish to a topic encrypted with the
  AWS-managed key; alert contents aren't sensitive. *Production:* a customer-managed key with a key policy
  for CloudWatch.

## 3. Delivery and infrastructure as code

- **Terraform is applied from my laptop.** *Production:* nobody applies locally. PR → `fmt`/`validate`/lint
  and security scan + `terraform plan` posted on the PR → review of code and plan → merge → CI applies
  exactly that plan, with an approval gate for prod. CI logs in with GitHub OIDC (a read-only plan role for
  PRs, an apply role only for `main`); people get read-only access plus a break-glass role; a nightly plan
  detects drift.
- **Argo CD polls Git every 30 seconds** (no webhook: Argo CD isn't reachable from GitHub without a domain).
  *Production:* GitHub webhook for instant syncs.

## 4. Kubernetes and networking

- **No S3 gateway endpoint.** Pods reach S3 (Loki's logs, and ECR image layers, which are stored in S3)
  through the NAT gateways, which bills NAT data processing per GB. A gateway endpoint is free, keeps S3
  traffic inside AWS's network off the NAT, and allows "only from this VPC" bucket policies and an endpoint
  policy against data exfiltration. A few lines in `vpc.tf`, no downtime.
- **Replica spread can drift between deploys.** Spread rules are only checked when a pod is scheduled;
  after an unplanned node loss (e.g. a spot reclaim), replicas can stay unbalanced until the next rollout.
  Rollout-caused imbalance is fixed.
- **Some add-ons run without memory requests** (Argo CD components, `aws-node`, `kube-proxy`, Pod Identity
  agent): the scheduler can't plan around their real usage. I added a 4th system node for headroom and
  gave every monitoring component explicit requests/limits. *Next step:* requests for the rest.

## 5. Data and backups

- **Backups stay in the same account and region** (SCP). *Production:* copies to a separate backup
  account/region, S3 replication or Object Lock, longer RDS retention (14-35 days instead of 7).
- **No caching tier.** The app has no cache layer, so an unused Redis would only add cost. If needed:
  ElastiCache in the database subnets for hot endpoints (tags, article lists).

## 6. Observability

- **The backend has no request logging and no application metrics.** It only logs startup, shutdown and
  errors (as multi-line text). Monitoring covers infrastructure (nodes, pods, ALB, RDS) and API requests
  via the nginx access logs. *Next step:* structured JSON request logs with a request ID shared with nginx,
  and Prometheus metrics per route (rate, errors, latency).
- **Dev has no monitoring or alerting** (cost). *Production:* dev/staging get monitoring too (e.g. a lighter
  stack, or one central monitoring for all clusters), so problems are found before prod.
- **No tracing.** *Next step:* OpenTelemetry.
- **Dashboards come from the chart only**; no app-specific dashboards kept in Git yet.
- **Metrics from Karpenter, Argo CD, External Secrets and CoreDNS aren't scraped yet** (their charts can
  add `ServiceMonitor`s).
- **One email address as the only alert channel.** *Production:* alerts to the team's Slack or Microsoft
  Teams channel as well as email (Alertmanager can post to Slack/Teams directly; CloudWatch alarms via the
  same SNS topic), so the whole team sees them, not one inbox.
