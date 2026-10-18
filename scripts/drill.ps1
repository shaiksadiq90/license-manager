<#
  Break-and-recover drill for the local Docker Compose stack.
  Run from the project folder in normal PowerShell:   .\scripts\drill.ps1
  Phases: healthy baseline -> stop the database -> outage (alert fires) -> start the database -> recovery (alert resolves)
#>
param([int]$BaselineSec = 90, [int]$OutageSec = 180, [int]$RecoverySec = 360)
$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Stamp($msg, $color = "Cyan") { Write-Host ("[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $msg) -ForegroundColor $color }
function Ready { curl.exe -s -m 3 -w " HTTP %{http_code}" http://127.0.0.1:3000/readyz }

# Steady background traffic so the SLO metrics have data
$traffic = Start-Job -ScriptBlock {
  $end = (Get-Date).AddMinutes(20)
  while ((Get-Date) -lt $end) {
    curl.exe -s -o NUL -m 2 http://127.0.0.1:3000/api/licenses
    curl.exe -s -o NUL -m 2 http://127.0.0.1:3000/healthz
    Start-Sleep -Milliseconds 250
  }
}

Stamp "Traffic started. Healthy baseline for $BaselineSec s. readyz ->$(Ready)" Green
Start-Sleep $BaselineSec

Stamp "BREAK: docker compose stop db" Red
docker compose stop db
Stamp "readyz ->$(Ready)" Yellow
Stamp "api    ->$(curl.exe -s -m 3 -w ' HTTP %{http_code}' http://127.0.0.1:3000/api/licenses)" Yellow
Stamp "healthz->$(curl.exe -s -m 3 -w ' HTTP %{http_code}' http://127.0.0.1:3000/healthz)  (process still up)" Yellow
Stamp "Outage for $OutageSec s: watch ErrorBudgetFastBurn go pending, then firing" Yellow
Start-Sleep $OutageSec

Stamp "RECOVER: docker compose start db" Green
docker compose start db
Start-Sleep 8
Stamp "readyz ->$(Ready)" Green
Stamp "Recovery window $RecoverySec s: availability climbs back to 100%, alert resolves" Green
Start-Sleep $RecoverySec

Stop-Job $traffic | Out-Null; Remove-Job $traffic | Out-Null
Stamp "Drill complete" Green
