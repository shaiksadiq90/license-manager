<#
  Run License Manager on local Kubernetes (minikube) - free, no AWS.
  Usage (normal PowerShell, from the project folder):  .\scripts\local-k8s.ps1
  Tear down:                                            .\scripts\local-k8s.ps1 -Down
#>
param([switch]$Down)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if ($Down) { helm uninstall license-manager; minikube stop; exit 0 }

Write-Host "==> Starting minikube (Calico CNI so NetworkPolicies are enforced)" -ForegroundColor Cyan
minikube status *> $null
if ($LASTEXITCODE -ne 0) { minikube start --driver=docker --cni=calico --cpus=2 --memory=4096 }
minikube addons enable metrics-server | Out-Null   # needed by the HorizontalPodAutoscaler

Write-Host "==> Building images inside minikube" -ForegroundColor Cyan
minikube image build -t license-manager-api:local backend
minikube image build -t license-manager-web:local frontend

Write-Host "==> Deploying with Helm" -ForegroundColor Cyan
helm upgrade --install license-manager k8s/helm/license-manager `
  -f k8s/helm/license-manager/values-local.yaml --wait --timeout 5m

kubectl get pods,svc,hpa,networkpolicy
Write-Host "`n==> Opening the app (keep this window open; Ctrl+C to stop the tunnel)" -ForegroundColor Green
minikube service web
