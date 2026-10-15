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
| http://localhost:8080 | Web UI |
| http://localhost:3000/api/licenses | API |
| http://localhost:3000/metrics | Prometheus metrics |
| http://localhost:9090 | Prometheus |
| http://localhost:3001 | Grafana (admin/admin), SLO folder |

Tests: `cd backend; npm test`

## 3. Kubernetes locally (no AWS cost)
```powershell
minikube start --cni=calico
minikube image build -t license-manager-api:latest backend
minikube image build -t license-manager-web:latest frontend
kubectl create secret generic license-db --from-literal=DATABASE_URL=postgres://...
helm install license-manager k8s/helm/license-manager
```

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
