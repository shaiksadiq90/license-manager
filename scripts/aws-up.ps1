<#
  Bring up the dev environment on AWS and hand deployment over to Argo CD.
    1. terraform apply (VPC, EKS, RDS, ECR) using the remote S3 state
    2. kubeconfig for the new cluster
    3. database secret, built from the RDS password that AWS keeps in Secrets Manager
    4. Argo CD + the license-manager Application (from then on, git is the source of truth)
  Cost: about $3-4 per day while it is up. Run .\scripts\aws-down.ps1 when finished.
#>
param([string]$Region = "us-east-1")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step "Checking tools and AWS login"
foreach ($t in "aws", "terraform", "kubectl", "helm") { if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "$t is not installed" } }
aws sts get-caller-identity --query Account --output text | Out-Null
if (-not (Test-Path infra/terraform/envs/dev/backend.hcl)) { throw "Create infra/terraform/envs/dev/backend.hcl from backend.hcl.example first (see docs/AWS-GITOPS.md)" }

Step "Terraform: VPC, EKS, RDS, ECR (15-20 minutes the first time)"
Push-Location infra/terraform/envs/dev
terraform init -backend-config=backend.hcl -input=false
terraform apply -auto-approve -input=false
$cluster  = terraform output -raw cluster_name
$dbHost   = terraform output -raw db_endpoint
$secretId = terraform output -raw db_secret_arn
Pop-Location

Step "kubeconfig for $cluster"
aws eks update-kubeconfig --name $cluster --region $Region
kubectl get nodes

Step "Database secret (password read from Secrets Manager, never written to disk)"
$creds = aws secretsmanager get-secret-value --secret-id $secretId --region $Region --query SecretString --output text | ConvertFrom-Json
$pw = [uri]::EscapeDataString($creds.password)
kubectl create namespace license-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl -n license-manager create secret generic license-db `
  --from-literal=DATABASE_URL="postgres://$($creds.username):$pw@${dbHost}:5432/licenses?sslmode=no-verify" `
  --dry-run=client -o yaml | kubectl apply -f -

Step "Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm 2>$null
helm repo update argo
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 7.6.12 --wait --timeout 10m
kubectl apply -f gitops/argocd/application.yaml

Step "Waiting for Argo CD to sync and the load balancer to get an address"
for ($i = 0; $i -lt 60; $i++) {
  $sync = kubectl -n argocd get application license-manager-dev -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>$null
  $lb   = kubectl -n license-manager get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
  Write-Host ("  {0}  sync/health: {1}  lb: {2}" -f (Get-Date -Format HH:mm:ss), $sync, $lb)
  if ($sync -eq "Synced/Healthy" -and $lb) { break }
  Start-Sleep 10
}

$argoPw = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
Write-Host "`nApp:     http://$lb" -ForegroundColor Green
Write-Host "Argo CD: kubectl -n argocd port-forward svc/argocd-server 8443:443  ->  https://127.0.0.1:8443  (user admin)" -ForegroundColor Green
Write-Host ("         password: " + [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($argoPw)))
Write-Host "`nIf pods show ImagePullBackOff, CI has not pushed images yet: push to main with AWS_DEPLOY_ENABLED=true." -ForegroundColor Yellow
Write-Host "Tear down when finished: .\scripts\aws-down.ps1" -ForegroundColor Yellow
