<#
  License Manager - DevOps toolchain installer for Windows.
  Run from an ADMINISTRATOR PowerShell:
     Set-ExecutionPolicy -Scope Process Bypass -Force
     .\scripts\setup-windows.ps1
  Safe to re-run: winget skips anything already installed.
#>
$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Start-Transcript -Path "$root\setup-log.txt" -Force | Out-Null

$tools = @(
  @{ id = "Git.Git";                     name = "Git" },
  @{ id = "OpenJS.NodeJS.LTS";           name = "Node.js LTS (includes npm/npx)" },
  @{ id = "Docker.DockerDesktop";        name = "Docker Desktop" },
  @{ id = "Hashicorp.Terraform";         name = "Terraform" },
  @{ id = "Amazon.AWSCLI";               name = "AWS CLI v2" },
  @{ id = "Kubernetes.kubectl";          name = "kubectl" },
  @{ id = "Helm.Helm";                   name = "Helm" },
  @{ id = "Kubernetes.minikube";         name = "minikube (local Kubernetes)" },
  @{ id = "AquaSecurity.Trivy";          name = "Trivy (image scanning)" },
  @{ id = "GitHub.cli";                  name = "GitHub CLI" },
  @{ id = "Microsoft.VisualStudioCode";  name = "VS Code" },
  @{ id = "Python.Python.3.12";          name = "Python 3.12" }
)

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "winget not found. Install 'App Installer' from the Microsoft Store, then re-run." -ForegroundColor Red; Stop-Transcript; exit 1
}

foreach ($t in $tools) {
  Write-Host "`n==> $($t.name)" -ForegroundColor Cyan
  winget install --id $t.id -e --silent --accept-package-agreements --accept-source-agreements
}

# Docker Desktop needs WSL2
Write-Host "`n==> Enabling WSL2 (needed by Docker Desktop)" -ForegroundColor Cyan
wsl --install --no-distribution

# Refresh PATH for this session
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

# VS Code extensions
if (Get-Command code -ErrorAction SilentlyContinue) {
  "hashicorp.terraform","ms-kubernetes-tools.vscode-kubernetes-tools","ms-azuretools.vscode-docker","redhat.vscode-yaml","github.vscode-github-actions" |
    ForEach-Object { code --install-extension $_ --force }
}

# Project dependencies

# Move the GitHub Actions pipeline into place
if (Test-Path "$root\ci\ci-cd.yml") {
  New-Item -ItemType Directory -Force "$root\.github\workflows" | Out-Null
  Move-Item -Force "$root\ci\ci-cd.yml" "$root\.github\workflows\ci-cd.yml"
  Remove-Item "$root\ci" -ErrorAction SilentlyContinue
}
# Initialise the git repo
if (-not (Test-Path "$root\.git") -and (Get-Command git -ErrorAction SilentlyContinue)) { git -C $root init -b main | Out-Null }
if (Get-Command npm -ErrorAction SilentlyContinue) {
  Write-Host "`n==> npm install (backend, frontend)" -ForegroundColor Cyan
  Push-Location "$root\backend";  npm install; npm test; Pop-Location
  Push-Location "$root\frontend"; npm install; Pop-Location
} else { Write-Host "Open a NEW PowerShell window and re-run to install npm packages." -ForegroundColor Yellow }

Write-Host "`n==> Versions" -ForegroundColor Green
foreach ($c in "git --version","node --version","docker --version","terraform version","aws --version","kubectl version --client","helm version --short","trivy --version","gh --version") {
  try { Invoke-Expression $c 2>$null | Select-Object -First 1 } catch { Write-Host "$c : not on PATH yet (restart terminal)" }
}
Stop-Transcript | Out-Null
"SETUP-COMPLETE" | Out-File "$root\setup-done.txt"
Write-Host "`nDone. Restart Windows if Docker Desktop or WSL asked you to, then: docker compose up --build" -ForegroundColor Green
