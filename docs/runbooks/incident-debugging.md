# Runbook: debugging an incident

Where to look first when something is wrong, organised by symptom. Most incidents follow the same path:
**what's alerting → what changed → which layer is broken → roll back or fix**.

## Before you start

- AWS CLI logged in, with cluster admin access to `hw-eks-prod` (an EKS access entry, see
  `environments/prod/eks.tf`), plus `kubectl`.
- Connect and check you're on the right cluster:

  ```bash
  aws eks update-kubeconfig --name hw-eks-prod --region us-east-1
  kubectl config current-context   # must end with cluster/hw-eks-prod
  ```
- Grafana and Argo CD have no public UI; open them with port-forwards (each in its own terminal):

  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80    # http://localhost:3000
  kubectl -n argocd port-forward svc/argocd-server 8080:443                       # https://localhost:8080
  # passwords (user admin)
  kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```

## Tools

I prefer working through UIs during an incident; they show the state and the relations between objects
faster than a series of commands:

- **[Lens](https://k8slens.dev/)** (Kubernetes desktop app, uses the same kubeconfig as `kubectl`): pods and
  their status, logs, events, `describe`, resource usage per pod/node, a shell into a container, all in one
  place.
- **Argo CD UI**: which app is out of sync or degraded, the resource tree of each app (Deployment →
  ReplicaSet → Pods), the **diff** between Git and the cluster, sync errors and the deploy **history**.
- **Grafana dashboards**: trends over time (when did it start, what else changed at that moment), plus
  logs (Loki) and AWS metrics (CloudWatch) next to each other.

The `kubectl` commands below are the equivalent for when a UI isn't available, and easy to copy into
a ticket or chat.

## First 5 minutes

1. **Read the alert.** The email says where it comes from: a CloudWatch alarm (`hw-alb-*`, `hw-rds-*`: the AWS
   side) or Alertmanager (a Kubernetes rule, e.g. `KubePodCrashLooping`, with namespace and pod).
2. **What changed?** Most incidents follow a change. Check the last deploys: Argo CD → the app → *History*, or
   the latest commits in `k8s-envs` (`deploy(backend): prod <sha>`), and recent `terraform apply`s.
3. **Overview**:

   ```bash
   kubectl -n argocd get applications           # anything not Synced / Healthy?
   kubectl get nodes                             # all Ready?
   kubectl get pods -A | grep -vE 'Running|Completed'
   kubectl -n prod get pods -o wide              # restarts, which nodes / zones
   ```
4. **Grafana**: *Alerting → Active notifications* (choose the **Alertmanager** source) for everything firing;
   dashboards *Kubernetes / Compute Resources / Namespace (Pods)* (namespace `prod`) and
   *Node Exporter / Nodes*.

## Where the logs are

| What | Where | Example |
|---|---|---|
| App pods (nginx access logs, backend) | Grafana → Explore → **Loki** | `{namespace="prod", app="hw-frontend-prod"} \| json \| status >= 500` |
| Any pod, by label | Loki (labels `namespace`, `app`, `pod`, `container`, `node`) | `{namespace="monitoring", pod=~"loki-.*"}` |
| Database (errors, slow queries > 1 s) | CloudWatch Logs `/aws/rds/instance/hw-rds-prod/postgresql` (also in Grafana → CloudWatch) | Logs Insights: `fields @timestamp, @message \| filter @message like /ERROR\|duration/` |
| EKS control plane (API, audit, auth) | CloudWatch Logs `/aws/eks/hw-eks-prod/cluster` | who deleted/changed a resource |
| Network (accepted/rejected traffic) | CloudWatch Logs `/aws/vpc-flow-log/<vpc-id>` | a security group blocking a connection |
| Crashed container's previous run | `kubectl -n prod logs <pod> --previous` | the error right before the restart |

Useful LogQL on the nginx access logs (every `/api` request passes through nginx):

```logql
# 5xx per URI, last 15 min
sum by (uri) (count_over_time({app="hw-frontend-prod"} | json | status >= 500 [15m]))
# slowest requests
{app="hw-frontend-prod"} | json | request_time > 1
```

## By symptom

### Site down or many 5xx (`hw-alb-target-5xx-prod`, `hw-alb-unhealthy-targets-prod`)

- **Frontend pods** Ready? `kubectl -n prod get pods -l app=hw-frontend-prod`. If none are Ready, the ALB has
  no healthy targets.
- **502/504 from nginx** means the backend isn't answering: check the backend pods and their readiness.
- **Backend readiness** checks the database (`/api/health/ready` returns 503 "database unavailable"): if all
  backend pods are NotReady at once, look at the database first (below).
- **Right after a deploy?** Roll back (see [Roll back](#roll-back)), then investigate.

### Slow responses (`hw-alb-latency-p95-prod`)

- Which URIs are slow: the LogQL `request_time` query above.
- **Backend under load**: HPA at its maximum (`kubectl -n prod get hpa`), CPU throttling in the
  *Namespace (Pods)* dashboard.
- **Database**: RDS CPU and connections (Grafana → CloudWatch, `AWS/RDS`), slow queries in the RDS log group.
- **Nodes**: memory/CPU pressure in *Node Exporter / Nodes*.

### Pods crash-looping or OOMKilled (`KubePodCrashLooping`)

```bash
kubectl -n prod describe pod <pod>     # Last State: reason (OOMKilled, Error), exit code, events
kubectl -n prod logs <pod> --previous  # output of the crashed run
```

- `OOMKilled` (exit 137): the container hit its memory limit; compare usage in the *Namespace (Pods)*
  dashboard with the limit in `k8s-envs`, raise it there (not with `kubectl edit`: Argo CD would revert it).
- Failing on start: missing config or secret (`kubectl -n prod get externalsecret`: is it `SecretSynced`?).

### Pods Pending

```bash
kubectl -n prod describe pod <pod>                      # Events: why it can't be scheduled
kubectl get nodeclaims                                  # nodes Karpenter is starting
kubectl -n kube-system logs deploy/karpenter --since=30m | grep -iE 'error|launch|nodeclaim'
```

- Usually Karpenter is just starting a node (1-2 minutes). Stuck: look for capacity errors (no spot
  capacity for the allowed instance types) or permission errors in Karpenter's logs.
- The spread rules deliberately keep a pod Pending until a node exists in the missing AZ / capacity type;
  that resolves once Karpenter's node is up.
- Monitoring pods with volumes can only run in the AZ of their EBS volume.

### Database problems

- **Backend can't connect**: backend logs in Loki; `PAM authentication failed for user "app_user"` means the
  IAM token was rejected (check the backend's IAM role, service account annotation, `rds-db:connect` policy).
- **Failover**: RDS Multi-AZ fails over in about 1-2 minutes; *RDS → Events* in the console shows it.
  Readiness takes backend pods out of traffic meanwhile and puts them back afterwards.
- **Storage / memory**: `hw-rds-free-storage-prod`, `hw-rds-freeable-memory-prod` alarms; storage grows
  automatically up to 100 GB.
- Data lost or corrupted: [restore runbook](restore-db.md).

### A deploy didn't arrive

Follow the delivery chain:

1. **CI** in the app repo: green? (tests, secret scan, image scan can stop it)
2. **ECR**: does the image tag exist?
3. **`k8s-envs`**: was the tag commit (`deploy(<app>): prod <sha>`) pushed?
4. **Argo CD**: app *Synced*? A sync error is shown on the app (`kubectl -n argocd get application
   hw-backend-prod -o yaml`, section `status.conditions`).
5. **Migration Job** failed? It stops the sync, old pods keep running:
   `kubectl -n prod logs job/hw-backend-migrate-prod`.
6. **Rollout stuck?** New pods not Ready: `kubectl -n prod rollout status deploy/hw-backend-prod`, then
   their logs. Old pods keep serving until new ones are Ready.

### Monitoring is down (`hw-monitoring-heartbeat-prod`)

The heartbeat from Alertmanager stopped arriving, so in-cluster alerts can't be trusted right now.

```bash
kubectl -n monitoring get pods
kubectl -n argocd get application monitoring
```

Check Alertmanager and Prometheus pods (OOM, Pending because of their volume's AZ) and whether the whole
cluster is reachable at all. CloudWatch alarms (RDS, ALB) keep working either way.

## Roll back

Everything in the cluster is deployed from Git, so a rollback is a Git change too:

```bash
# in k8s-envs: undo the tag bump of the bad deploy
git revert <commit of "deploy(backend): prod <sha>">
git push
```

Argo CD syncs the previous image within ~30 seconds. Don't fix things with `kubectl edit` / `kubectl scale`
on Argo CD-managed resources: self-heal reverts them. For an emergency change, disable auto-sync on that
app in Argo CD first, and put the fix into Git afterwards.

Database migrations aren't rolled back automatically: if a deploy included a migration, check whether the
previous version still works with the new schema before reverting.

## Afterwards

Write a short post-mortem: what happened, impact and duration, root cause, what detected it (or why nothing
did), and follow-ups (a missing alert, a missing runbook step).
