<#
  Hands-free live demo of the local Docker Compose stack:
    1. the app   2. the pipeline   3. the SLO dashboard   4. a break-and-recover drill
  It lays out its own windows (browser on the left, this console on the right) and, with -Record,
  saves a screen frame every second to demo-frames\ so the run can be turned into a video.

  Start the stack first (docker compose up --build -d), then run from the project folder in a classic console:
      conhost.exe powershell -ExecutionPolicy Bypass -File .\scripts\demo.ps1 -Record
#>
param([switch]$Record, [int]$MaxOutageSec = 300, [int]$MaxRecoverySec = 600)
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"   # no progress bars flashing in the recording
Set-Location (Split-Path $PSScriptRoot -Parent)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials } catch { }

$Api = "http://127.0.0.1:3000"; $Web = "http://127.0.0.1:8080"; $Prom = "http://127.0.0.1:9090"; $Graf = "http://127.0.0.1:3001"
$Repo = "shaiksadiq90/license-manager"
$runId = Get-Date -Format yyyyMMdd-HHmmss
$log = Join-Path (Get-Location) "demo-log.txt"
$events = New-Object System.Collections.Generic.List[string]
$events.Add("# unix_ms`tevent")

# ---------------- window layout helpers ----------------
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class DemoWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct FONTEX { public uint cbSize; public uint nFont; public short X; public short Y; public int Family; public int Weight;
                         [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Face; }
  [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref FONTEX f);
  public static bool SetConsoleFont(string face, short height) {
    FONTEX f = new FONTEX(); f.cbSize = (uint)Marshal.SizeOf(typeof(FONTEX)); f.Y = height; f.Family = 54; f.Weight = 400; f.Face = face;
    return SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref f);
  }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  const uint SHOW = 0x0040, NOACTIVATE = 0x0010, NOMOVE = 0x0002, NOSIZE = 0x0001;

  // Put a window exactly on (x, y, w, h), compensating for the invisible resize borders, and keep it on top
  public static void Place(IntPtr h, int x, int y, int w, int hgt) {
    IntPtr top = new IntPtr(-1);
    ShowWindow(h, 9);
    SetWindowPos(h, top, x, y, w, hgt, SHOW | NOACTIVATE);
    RECT wr, fr;
    if (GetWindowRect(h, out wr) && DwmGetWindowAttribute(h, 9, out fr, Marshal.SizeOf(typeof(RECT))) == 0) {
      int l = fr.L - wr.L, t = fr.T - wr.T, r = wr.R - fr.R, b = wr.B - fr.B;
      SetWindowPos(h, top, x - l, y - t, w + l + r, hgt + t + b, SHOW | NOACTIVATE);
    }
  }
  public static void Unpin(IntPtr h) { SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, NOMOVE | NOSIZE | NOACTIVATE); }

  // First visible, titled top-level window that belongs to the given process
  public static IntPtr FindWindowOf(int pid) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate (IntPtr h, IntPtr p) {
      int owner; GetWindowThreadProcessId(h, out owner);
      if (owner == pid && IsWindowVisible(h)) {
        StringBuilder sb = new StringBuilder(256); GetWindowText(h, sb, 256);
        if (sb.Length > 0) { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@
[void][DemoWin]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$wa  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$dpi = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96.0
$fit = $wa.Width / 1600.0   # zoom levels below are for a 1600 px wide screen; scale them to this one
$split = [int]($wa.Width * 0.64)
$sideTopH = [int]($wa.Height * 0.46)
$L = @{ Main       = @($wa.X, $wa.Y, $split, $wa.Height)
        Side       = @(($wa.X + $split), $wa.Y, ($wa.Width - $split), $wa.Height)
        SideTop    = @(($wa.X + $split), $wa.Y, ($wa.Width - $split), $sideTopH)
        SideBottom = @(($wa.X + $split), ($wa.Y + $sideTopH), ($wa.Width - $split), ($wa.Height - $sideTopH)) }

$con = [DemoWin]::GetConsoleWindow()
$fontPx = [int][Math]::Max(16, [Math]::Min(28, ($wa.Width - $split) / 64 / 0.55))
[void][DemoWin]::SetConsoleFont("Consolas", $fontPx)
function Place-Console($rect) {
  [DemoWin]::Place($con, $rect[0], $rect[1], $rect[2], $rect[3])
  Start-Sleep -Milliseconds 300
  try { $r = $Host.UI.RawUI; $w = $r.WindowSize.Width; if ($r.BufferSize.Width -ne $w) { $r.BufferSize = New-Object Management.Automation.Host.Size($w, 3000) } } catch { }
}

$browser = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
             "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") |
           Where-Object { Test-Path $_ } | Select-Object -First 1
$profileRoot = Join-Path $env:TEMP "license-manager-demo\$runId"

# Each demo window is its own small browser instance (separate temporary profile) so it can have its own zoom level
function Open-Window($name, $url, $rect, [double]$zoom = 1.0) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $cargs = @("--user-data-dir=`"$(Join-Path $profileRoot $name)`"", "--no-first-run", "--no-default-browser-check", "--disable-sync",
             "--hide-crash-restore-bubble", "--disable-search-engine-choice-screen", "--force-device-scale-factor=$(($zoom * $fit).ToString($inv))",
             "--window-position=$([int]($rect[0] / $dpi)),$([int]($rect[1] / $dpi))", "--window-size=$([int]($rect[2] / $dpi)),$([int]($rect[3] / $dpi))",
             "--app=$url")
  $p = Start-Process -FilePath $browser -ArgumentList $cargs -PassThru
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 80 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = [DemoWin]::FindWindowOf($p.Id) }
  if ($h -ne [IntPtr]::Zero) { [DemoWin]::Place($h, $rect[0], $rect[1], $rect[2], $rect[3]) }
  [pscustomobject]@{ Name = $name; Proc = $p; Handle = $h }
}
function Close-Window($w) {
  if (-not $w -or $w.Proc.HasExited) { return }
  [void]$w.Proc.CloseMainWindow()
  if (-not $w.Proc.WaitForExit(6000)) { Stop-Process -Id $w.Proc.Id -Force -ErrorAction SilentlyContinue }
}

# ---------------- narration helpers ----------------
# Timeline kept in memory and rewritten each time, so a sync tool or viewer holding the file open never breaks the demo
function Mark($what) {
  $events.Add(("{0}`t{1}" -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), $what))
  for ($i = 0; $i -lt 3; $i++) { try { [IO.File]::WriteAllLines($log, $events); return } catch { Start-Sleep -Milliseconds 200 } }
}
function Out-Wrapped([string]$text, [string]$color, [string]$prefix) {
  $width = [Math]::Max(30, $Host.UI.RawUI.WindowSize.Width - 1)
  $indent = " " * $prefix.Length; $lead = $prefix; $cur = ""
  foreach ($word in ($text -split " ")) {
    if ($cur -ne "" -and ($lead.Length + $cur.Length + 1 + $word.Length) -gt $width) { Write-Host ($lead + $cur) -ForegroundColor $color; $lead = $indent; $cur = $word }
    elseif ($cur -eq "") { $cur = $word } else { $cur += " " + $word }
  }
  Write-Host ($lead + $cur) -ForegroundColor $color
}
function Say($t, $c = "Gray") { Out-Wrapped $t $c "" }
function Step($t, $c = "Cyan") { Out-Wrapped $t $c ("[{0}] " -f (Get-Date -Format HH:mm:ss)) }
function Phase($n, $title) {
  Mark "phase$n`t$title"
  Clear-Host
  Write-Host " LICENSE MANAGER - LIVE DEMO " -ForegroundColor Black -BackgroundColor Gray -NoNewline
  Write-Host ("  {0}/4 " -f $n) -ForegroundColor DarkGray
  Write-Host ""
  Write-Host (" {0}  {1} " -f $n, $title.ToUpper()) -ForegroundColor Black -BackgroundColor Cyan
  Write-Host ""
}
function Hold($sec) { Start-Sleep -Seconds $sec }

# ---------------- HTTP helpers ----------------
function Call($method, $path, $body) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Method $method -Uri "$Api$path" -ContentType "application/json" -Body $body -TimeoutSec 5
    return [pscustomobject]@{ Code = [int]$r.StatusCode; Body = [string]$r.Content }
  } catch [System.Net.WebException] {
    $resp = $_.Exception.Response
    if ($resp) {
      $body = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { try { (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch { "" } }
      return [pscustomobject]@{ Code = [int]$resp.StatusCode; Body = [string]$body }
    }
    return [pscustomobject]@{ Code = 0; Body = $_.Exception.Message }
  } catch { return [pscustomobject]@{ Code = 0; Body = $_.Exception.Message } }
}
function Show-Call($method, $path, $body, $note) {
  $r = Call $method $path $body
  $shown = if ($body) { "$method $path $body" } else { "$method $path" }
  Step "> $shown" "White"
  $c = if ($r.Code -ge 500 -or $r.Code -eq 0) { "Red" } elseif ($r.Code -ge 400) { "Yellow" } else { "Green" }
  $b = if ($r.Body.Length -gt 90) { $r.Body.Substring(0, 90) + "..." } else { $r.Body }
  Say ("  HTTP {0}  {1}" -f $r.Code, $b) $c
  if ($note) { Say "  $note" "DarkGray" }
  $r
}
function Probe($path) { $r = Call "GET" $path $null; "{0,-16} HTTP {1}  {2}" -f $path, $r.Code, $r.Body }
function Wait-Url($url, $sec = 120) {
  $end = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $end) { & curl.exe -sf -o NUL -m 3 $url; if ($LASTEXITCODE -eq 0) { return $true }; Start-Sleep 2 }
  $false
}
function PromValue($q) {
  try { $r = (Invoke-RestMethod -UseBasicParsing "$Prom/api/v1/query?query=$([uri]::EscapeDataString($q))" -TimeoutSec 5).data.result
        if ($r) { return [double]$r[0].value[1] } } catch { }
  $null
}
function AlertState {
  try { $a = @((Invoke-RestMethod -UseBasicParsing "$Prom/api/v1/alerts" -TimeoutSec 5).data.alerts | Where-Object { $_.labels.alertname -eq "ErrorBudgetFastBurn" })
        if ($a.Count -gt 0) { return [string]$a[0].state } else { return "inactive" } } catch { return "unknown" }
}
function Slo-Line {
  $av = PromValue "slo:availability:ratio_rate5m"; $p95 = PromValue "slo:latency_p95:5m"; $st = AlertState
  $avs = if ($av -ne $null) { "{0:N2}%" -f ($av * 100) } else { "n/a" }
  $ps  = if ($p95 -ne $null -and -not [double]::IsNaN($p95)) { "{0:N0} ms" -f ($p95 * 1000) } else { "n/a" }
  [pscustomobject]@{ Text = "availability $avs   p95 $ps   alert $st"; Avail = $av; State = $st }
}

# ================= 0. setup =================
$Host.UI.RawUI.WindowTitle = "License Manager - live demo"
Clear-Host
Place-Console $L.Side
if (-not $browser) { Say "Chrome or Edge not found." "Red"; return }
Say "Checking the stack..." "DarkGray"
foreach ($u in @("$Api/readyz", "$Web/", "$Prom/-/ready", "$Graf/api/health")) {
  if (-not (Wait-Url $u 120)) { Say "Not reachable: $u  (run: docker compose up --build -d)" "Red"; return }
}

# Steady background traffic so the SLO metrics have data
$traffic = Start-Job -ScriptBlock {
  $end = (Get-Date).AddMinutes(30)
  while ((Get-Date) -lt $end) {
    curl.exe -s -o NUL -m 2 http://127.0.0.1:3000/api/licenses
    curl.exe -s -o NUL -m 2 http://127.0.0.1:3000/healthz
    Start-Sleep -Milliseconds 250
  }
}

# ================= 1. the app =================
$existing = 0; try { $existing = ((Call "GET" "/api/licenses" $null).Body | ConvertFrom-Json | Measure-Object).Count } catch { }
if ($existing -eq 0) { foreach ($s in @(@("AutoCAD", 25), @("Revit", 15), @("Fusion", 8))) { [void](Call "POST" "/api/licenses" ("{""name"":""$($s[0])"",""seats"":$($s[1])}")) } }
$app = Open-Window "app" "$Web/" $L.Main 1.0
Place-Console $L.Side
if ($Record) {
  $frames = Join-Path (Get-Location) "demo-frames\$runId"
  $capture = Start-Job -FilePath (Join-Path $PSScriptRoot "capture.ps1") -ArgumentList $frames, 1000, 30
}
Phase 1 "The app"
Mark "recording-start"
Say "React web UI on :8080 -> Node/Express API on :3000 -> PostgreSQL. Every API call is timed into a Prometheus histogram." "Gray"
Say "Changes below go through the same REST API the UI uses; the page refreshes every 3 s." "DarkGray"
Say ""
Hold 6
$created = Show-Call "POST" "/api/licenses" '{"name":"Maya","seats":10}' "Created. Watch it appear in the table."
$id = try { ($created.Body | ConvertFrom-Json).id } catch { $null }
Mark "app-create"; Hold 6
[void](Show-Call "POST" "/api/licenses" '{"name":"Bad row","seats":0}' "Validation: bad input is a clean 400, never saved.")
Mark "app-validate"; Hold 5
if ($id) {
  [void](Show-Call "PUT" "/api/licenses/$id" '{"status":"suspended"}' "Suspended.")
  Mark "app-suspend"; Hold 6
  [void](Show-Call "PUT" "/api/licenses/$id" '{"status":"active"}' "Reactivated.")
  Mark "app-activate"; Hold 6
  [void](Show-Call "DELETE" "/api/licenses/$id" $null "Deleted.")
  Mark "app-delete"; Hold 6
}

# ================= 2. the pipeline =================
$runUrl = "https://github.com/$Repo/actions"; $run = $null; $jobs = @()
try {
  $h = @{ "User-Agent" = "license-manager-demo"; "Accept" = "application/vnd.github+json" }
  $run = (Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/actions/runs?branch=main&status=success&per_page=1" -Headers $h -TimeoutSec 10).workflow_runs[0]
  if ($run) { $runUrl = $run.html_url; $jobs = @((Invoke-RestMethod -UseBasicParsing $run.jobs_url -Headers $h -TimeoutSec 10).jobs) }
} catch { }
$gh = Open-Window "pipeline" $runUrl $L.Main 0.8
Close-Window $app
Phase 2 "The pipeline"
Say "GitHub Actions runs on every push to main. Nothing is deployed unless every gate passes." "Gray"
Say ""
if ($run) {
  Step ("Run #{0}  {1}  ({2})" -f $run.run_number, $run.conclusion.ToUpper(), $run.head_sha.Substring(0, 7)) "Green"
  Say ("  " + $run.display_title) "DarkGray"
  Say ""
  foreach ($j in $jobs) {
    $sec = try { [int]([datetime]$j.completed_at - [datetime]$j.started_at).TotalSeconds } catch { 0 }
    $res = if ($j.conclusion) { $j.conclusion } else { $j.status }
    $c = switch ($res) { "success" { "Green" } "skipped" { "DarkGray" } default { "Yellow" } }
    Say ("  {0,-18} {1,-8} {2,4}s" -f $j.name, $res, [Math]::Max(0, $sec)) $c
  }
  Say ""
}
Say "Gates: unit tests | terraform fmt + validate | helm lint | Trivy blocks fixable HIGH/CRITICAL CVEs." "Gray"
Say "Deploy (OIDC to AWS, no stored keys; helm --atomic rolls back a bad release) runs only when AWS deploys are switched on, so it shows as skipped." "DarkGray"
Mark "pipeline-shown"
Hold 24

# ================= 3. the SLO dashboard =================
$graf = Open-Window "grafana" "$Graf/d/license-slo/?orgId=1&refresh=5s&from=now-10m&to=now&kiosk" $L.Main 0.75
Close-Window $gh
Place-Console $L.SideBottom
$app2 = Open-Window "app-small" "$Web/" $L.SideTop 0.62
Phase 3 "SLO dashboard"
Say "Targets from the user's side: 99.9% of requests succeed, p95 latency under 500 ms." "Gray"
Say "Page: ErrorBudgetFastBurn, error ratio above 14.4 x 0.1% for 2 min (budget gone in ~2 days)." "Gray"
Say ""
for ($i = 0; $i -lt 3; $i++) { Step (Slo-Line).Text "Green"; Hold 7 }
Mark "dashboard-baseline"

# ================= 4. break and recover =================
Phase 4 "Break-and-recover drill"
Step "BREAK: docker compose stop db" "Red"
Mark "drill-break"
docker compose stop db 2>&1 | ForEach-Object { Say ("  " + $_) "DarkGray" }
$tBreak = Get-Date
Start-Sleep 2
Say ("  " + (Probe "/readyz")) "Yellow"
Say ("  " + (Probe "/api/licenses")) "Yellow"
Say ("  " + (Probe "/healthz") + "  <- process stays up") "Green"
Say "Users get a fast, clean 503 and the UI keeps the last known data." "DarkGray"
Mark "drill-probed"
$last = ""; $tFire = $null; $tick = 0
while (((Get-Date) - $tBreak).TotalSeconds -lt $MaxOutageSec) {
  Start-Sleep 5; $tick++
  $s = Slo-Line
  if ($s.State -ne $last -or ($tick % 4) -eq 0) { Step $s.Text $(if ($s.State -eq "firing") { "Red" } else { "Yellow" }); if ($s.State -ne $last) { Mark "alert-$($s.State)" }; $last = $s.State }
  if ($s.State -eq "firing") { $tFire = Get-Date; break }
}
if ($tFire) {
  Step ("PAGE: ErrorBudgetFastBurn FIRING, {0:m\:ss} after the break" -f ($tFire - $tBreak)) "Red"
  Say "Mitigate first: restart the dependency (fastest, lowest risk; no code changed)." "DarkGray"
  Hold 12
}
Step "RECOVER: docker compose start db" "Green"
Mark "drill-recover"
docker compose start db 2>&1 | ForEach-Object { Say ("  " + $_) "DarkGray" }
$tStart = Get-Date
$ok = $false; for ($i = 0; $i -lt 60 -and -not $ok; $i++) { Start-Sleep 1; $ok = (Call "GET" "/readyz" $null).Code -eq 200 }
Say ("  " + (Probe "/readyz") + ("  after {0:N0} s" -f ((Get-Date) - $tStart).TotalSeconds)) "Green"
for ($i = 0; $i -lt 15 -and (Call "GET" "/api/licenses" $null).Code -ne 200; $i++) { Start-Sleep 1 }
Mark "drill-ready"
Say "Verify from the user's side: a real write, then the SLO." "DarkGray"
$smoke = Show-Call "POST" "/api/licenses" '{"name":"Smoke test","seats":1}' $null
try { [void](Show-Call "DELETE" "/api/licenses/$(($smoke.Body | ConvertFrom-Json).id)" $null $null) } catch { }
Say "Availability recovers as the outage leaves the 5-minute window." "DarkGray"
Mark "drill-verify"
$tick = 0; $tResolved = $null; $last = ""
while (((Get-Date) - $tStart).TotalSeconds -lt $MaxRecoverySec) {
  Start-Sleep 5; $tick++
  $s = Slo-Line
  if ($s.State -ne $last -or ($tick % 6) -eq 0) { Step $s.Text $(if ($s.State -eq "inactive") { "Green" } else { "Yellow" }); if ($s.State -ne $last) { Mark "alert-$($s.State)" }; $last = $s.State }
  if ($s.State -eq "inactive" -and $s.Avail -ne $null -and $s.Avail -ge 0.999) { $tResolved = Get-Date; break }
}
Mark "drill-resolved"
Say ""
if ($tResolved) { Step ("RECOVERED: alert resolved, availability back above 99.9%, {0:m\:ss} after restart" -f ($tResolved - $tStart)) "Green" }
Say ""
Say "Lessons: drills exposed a crash when the database went away, then slow 503s. Now a circuit breaker answers 503 instantly while a background health check waits for the database; unit tests guard both." "Gray"
Mark "demo-end"
Hold 15

# ================= cleanup =================
Stop-Job $traffic -ErrorAction SilentlyContinue; Remove-Job $traffic -Force -ErrorAction SilentlyContinue
if ($capture) { New-Item -ItemType File -Force (Join-Path $frames "STOP") | Out-Null; Wait-Job $capture -Timeout 15 | Out-Null; Remove-Job $capture -Force -ErrorAction SilentlyContinue
                Say ("Frames saved: {0}" -f $frames) "DarkGray" }
Close-Window $graf; Close-Window $app2
[DemoWin]::Unpin($con)
Say "Demo finished. Timeline: $log" "DarkGray"
