# Runbook: real AWS deployment with GitOps

**Goal:** run License Manager on AWS for real, deployed the GitOps way, and tear it down cleanly. Keep the evidence.

```
git push ─► GitHub Actions ─► test · terraform · helm lint · build · Trivy scan ─► push image to ECR
                                                                                   │
                                          commit new image tag to gitops/envs/dev/values.yaml
                                                                                   │
EKS cluster ◄── Argo CD (inside the cluster) watches git and syncs ◄───────────────┘
```

CI never logs in to the cluster. **Git is the source of truth.** If someone changes the cluster by hand, Argo CD reverts it (self-heal). To roll back, revert the commit.

## Files

| File | Purpose |
|---|---|
| `infra/terraform/bootstrap/main.tf` | One-time setup: S3 state bucket (versioned, encrypted), DynamoDB lock table, GitHub OIDC role (ECR push only) |
| `infra/terraform/envs/dev/backend.hcl.example` | Remote state settings. Copy to `backend.hcl` (git-ignored) |
| `infra/terraform/envs/dev/main.tf` | VPC, EKS, RDS, ECR. Dev settings allow a clean destroy |
| `gitops/argocd/application.yaml` | Argo CD app: Helm chart + dev values, auto-sync, prune, self-heal |
| `gitops/envs/dev/values.yaml` | Desired state of dev. CI updates the image tags |
| `.github/workflows/ci-cd.yml` | The `gitops-update` job replaces the old `helm upgrade` deploy |
| `scripts/aws-up.ps1` / `aws-down.ps1` | Bring dev up / tear it down |

## One-time setup (about 10 minutes)

```powershell
aws configure                                   # your own IAM user, region us-east-1
cd infra/terraform/bootstrap
terraform init; terraform apply                 # note the three outputs
copy ..\envs\dev\backend.hcl.example ..\envs\dev\backend.hcl   # paste state_bucket + lock_table
```

In GitHub, under **Settings → Secrets and variables → Actions**:
- secret `AWS_DEPLOY_ROLE_ARN` = the `deploy_role_arn` output
- variable `AWS_DEPLOY_ENABLED` = `true`

## Each session

```powershell
.\scripts\aws-up.ps1        # ~20 min: infra, Argo CD, app
git commit --allow-empty -m "deploy" ; git push   # CI builds, scans, pushes, bumps the tag; Argo CD deploys
.\scripts\aws-down.ps1      # ~15 min: everything except the bootstrap stack
```

**Cost:** about $3–4 per day while it's up: the EKS control plane, two t3.small nodes, one NAT gateway, db.t3.micro and a load balancer. Bootstrap costs cents per month. Set an AWS Budget alert at $20.

## Evidence to capture (for the portfolio)

1. `terraform apply` summary and `kubectl get nodes`
2. Argo CD UI: the app shown **Synced / Healthy** with its resource tree
3. The app working through the AWS load balancer URL
4. A deploy: push a commit → CI bumps the tag → Argo CD rolls the new version out
5. **Self-heal:** `kubectl scale deploy api --replicas=0 -n license-manager` → Argo CD restores 2 replicas
6. **Rollback:** `git revert` the deploy commit → Argo CD goes back to the previous image
7. Grafana / Prometheus pointed at the cluster (optional)
8. `terraform destroy` finished, and the AWS bill for the day

## Talking points

- **Why GitOps:** every change is a reviewed commit, so there's an audit trail. Rollback is `git revert`. The cluster can't drift from git. CI holds no cluster credentials.
- **Why remote state:** a team can't share local state. The DynamoDB lock stops two people applying at once, and versioning lets you recover a corrupted state file.
- **Why the bootstrap is separate:** the state bucket can't store its own state, so it's created once with local state and protected from deletion.
- **Trade-off:** the database password goes into a Kubernetes Secret from the script. Next step is External Secrets Operator, which syncs it from Secrets Manager automatically and rotates it.
- **Trade-off:** `sslmode=no-verify` encrypts the connection to the database but doesn't verify the server's certificate. Next step is to mount the RDS certificate bundle and use `verify-full`.
