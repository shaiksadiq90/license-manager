# License Manager - DevOps Showcase

Simple license CRUD app (Node.js + Express + TypeScript, React, PostgreSQL). The point is the platform around it: Terraform on AWS (VPC, EKS, RDS, ECR), Helm, GitHub Actions with Trivy scanning, Prometheus + Grafana Service Level Objective dashboards, and disaster recovery runbooks.

## 1. Install tools (Windows, once)
Open PowerShell **as Administrator** in this folder:
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\setup-windows.ps1
```
Installs Git, Node.js LTS, Docker Desktop, Terraform, AWS CLI, kubectl, Helm, minikube, Trivy, GitHub CLI, VS Code + extensions, then npm packages. Restart Windows if prompted.

## 2. Run locally
```powershell
docker compose up --build
```
| URL | What |
|---|---|
| http://127.0.0.1:8080 | Web UI |
| http://127.0.0.1:3000/api/licenses | API |
| http://127.0.0.1:3000/metrics | Prometheus metrics |
| http://127.0.0.1:9090 | Prometheus |
| http://127.0.0.1:3001 | Grafana (admin/admin), SLO folder |

Tests: `cd backend; npm test`

## 3. Kubernetes locally (no AWS cost)
```powershell
.\scripts\local-k8s.ps1          # minikube + Calico, builds images, helm install, opens the app
.\scripts\local-k8s.ps1 -Down    # remove
```
Practice drills: `kubectl delete pod -l app=api` (self-healing), `helm rollback license-manager 1`, `kubectl get events --sort-by=.lastTimestamp`.

## 4. Deploy to AWS
```powershell
aws configure
cd infra/terraform/envs/dev
terraform init; terraform plan; terraform apply
```
Then set the `AWS_DEPLOY_ROLE_ARN` GitHub secret and push to `main`. **Run `terraform destroy` afterwards** (~$100/month otherwise).

## Docs
- [Architecture](docs/ARCHITECTURE.md)
- [Service Level Objectives](docs/SLO.md)
- [Disaster Recovery](docs/DISASTER-RECOVERY.md)
