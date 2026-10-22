<#
  Tear the dev environment down completely, so nothing keeps billing.
  Order matters: delete the app first so Kubernetes removes the AWS load balancer it created;
  a leftover load balancer would block the VPC from being destroyed.
  The bootstrap stack (state bucket, lock table, GitHub role) is kept: it costs cents per month.
#>
param([string]$Region = "us-east-1")
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step "Removing the app (and its load balancer)"
kubectl -n argocd delete application license-manager-dev --ignore-not-found --wait=true
kubectl delete namespace license-manager --ignore-not-found --wait=true --timeout=5m
for ($i = 0; $i -lt 30; $i++) {
  $left = aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?contains(LoadBalancerName, 'k8s')].LoadBalancerName" --output text
  $classic = aws elb describe-load-balancers --region $Region --query "LoadBalancerDescriptions[].LoadBalancerName" --output text
  if (-not $left -and -not $classic) { break }
  Write-Host "  waiting for load balancers to be deleted..."; Start-Sleep 10
}
helm uninstall argocd -n argocd 2>$null

Step "Terraform destroy (10-15 minutes)"
Push-Location infra/terraform/envs/dev
terraform init -backend-config=backend.hcl -input=false | Out-Null
terraform destroy -auto-approve -input=false
$code = $LASTEXITCODE
Pop-Location

if ($code -eq 0) { Write-Host "`nDev environment destroyed. Billing for it has stopped." -ForegroundColor Green }
else { Write-Host "`nDestroy reported errors; run this script again (it is safe to repeat)." -ForegroundColor Red }
