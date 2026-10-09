# One-shot demo launcher. Run from a normal PowerShell window and KEEP IT OPEN:
#   powershell -ExecutionPolicy Bypass -File scripts\demo.ps1
# Ctrl+C stops the tunnel (containers keep running).
#
# Steps: Docker Desktop -> docker compose up -> cloudflared tunnel -> N8N_WEBHOOK_URL in .env
#        -> restart n8n -> smoke test through the public URL -> print the URLs for ElevenLabs.
param(
    [switch]$NoWait   # exit after the checks instead of keeping the tunnel attached (used for testing)
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$port = 5679
$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
if (-not (Test-Path $cloudflared)) { $cloudflared = "cloudflared" }

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "    ERR $msg" -ForegroundColor Red; exit 1 }

# --- 1. Docker Desktop -------------------------------------------------------
Step "Docker Desktop"
$dockerUp = $false
cmd /c "docker info >nul 2>&1"; $dockerUp = ($LASTEXITCODE -eq 0)
if (-not $dockerUp) {
    $exe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $exe)) { Fail "Docker Desktop not found at $exe" }
    Start-Process $exe
    Write-Host "    starting Docker Desktop, waiting up to 3 minutes..."
    $deadline = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Seconds 5
        cmd /c "docker info >nul 2>&1"; $dockerUp = ($LASTEXITCODE -eq 0)
    } until ($dockerUp -or (Get-Date) -gt $deadline)
    if (-not $dockerUp) { Fail "Docker engine did not come up. Open Docker Desktop and check it." }
}
Ok "engine running"

# --- 2. Stack ------------------------------------------------------------------
Step "docker compose up -d"
cmd /c "docker compose up -d 2>&1" | Where-Object { $_ -match "Started|Running|Healthy|Created" } | ForEach-Object { Write-Host "    $_" }
$deadline = (Get-Date).AddMinutes(2)
$n8nUp = $false
do {
    Start-Sleep -Seconds 3
    try { $r = Invoke-WebRequest -Uri "http://localhost:$port/healthz" -UseBasicParsing -TimeoutSec 5; $n8nUp = ($r.StatusCode -eq 200) } catch { }
} until ($n8nUp -or (Get-Date) -gt $deadline)
if (-not $n8nUp) { Fail "n8n not answering on http://localhost:$port (docker logs voltaluce_n8n)" }
Ok "n8n up on http://localhost:$port"

# --- 3. Tunnel ----------------------------------------------------------------
Step "Cloudflare quick tunnel (HTTP/2)"
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
$log = Join-Path $env:TEMP "cloudflared-voltaluce.log"
Remove-Item $log -Force -ErrorAction SilentlyContinue
$tunnel = Start-Process -FilePath $cloudflared -ArgumentList "tunnel","--url","http://localhost:$port","--protocol","http2","--no-autoupdate" `
    -RedirectStandardError $log -PassThru -WindowStyle Hidden
$url = $null
$deadline = (Get-Date).AddSeconds(40)
do {
    Start-Sleep -Seconds 2
    if (Test-Path $log) {
        $m = Select-String -Path $log -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" | Select-Object -First 1
        if ($m) { $url = $m.Matches[0].Value }
    }
} until ($url -or (Get-Date) -gt $deadline)
if (-not $url) { Fail "no tunnel URL after 40 s (see $log)" }
Ok "tunnel $url"

# --- 4. Point n8n at the public URL --------------------------------------------
Step "N8N_WEBHOOK_URL in .env and n8n restart"
$envFile = Join-Path $root ".env"
$content = Get-Content $envFile -Raw
if ($content -match "(?m)^N8N_WEBHOOK_URL=") {
    $content = $content -replace "(?m)^N8N_WEBHOOK_URL=.*$", "N8N_WEBHOOK_URL=$url/"
} else {
    $content = $content.TrimEnd() + "`nN8N_WEBHOOK_URL=$url/`n"
}
[System.IO.File]::WriteAllText($envFile, $content)
cmd /c "docker compose up -d n8n 2>&1" | Out-Null
$deadline = (Get-Date).AddMinutes(2)
$n8nUp = $false
do {
    Start-Sleep -Seconds 3
    try { $r = Invoke-WebRequest -Uri "http://localhost:$port/healthz" -UseBasicParsing -TimeoutSec 5; $n8nUp = ($r.StatusCode -eq 200) } catch { }
} until ($n8nUp -or (Get-Date) -gt $deadline)
if (-not $n8nUp) { Fail "n8n did not come back after restart" }
Ok "n8n restarted with public URL"

# --- 5. Smoke test through the tunnel ------------------------------------------
Step "Smoke test via tunnel"
$key = (Get-Content $envFile | Where-Object { $_ -match "^WEBHOOK_API_KEY=" }) -replace "^WEBHOOK_API_KEY=", ""
$body = '{"codice_cliente":"CL-00001"}'
$ok = $false
for ($i = 1; $i -le 5 -and -not $ok; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "$url/webhook/get-ultima-bolletta" -Method Post -ContentType "application/json" `
             -Headers @{ "x-api-key" = $key } -Body $body -UseBasicParsing -TimeoutSec 20
        $ok = ($r.StatusCode -eq 200)
    } catch { Start-Sleep -Seconds 4 }
}
if (-not $ok) { Fail "get-ultima-bolletta via tunnel did not return 200 (is the workflow published?)" }
Ok "get-ultima-bolletta -> 200 through the tunnel"
foreach ($p in "invia-autolettura", "apri-ticket", "post-call") {
    try {
        Invoke-WebRequest -Uri "$url/webhook/$p" -Method Post -ContentType "application/json" -Body "{}" -UseBasicParsing -TimeoutSec 20 | Out-Null
        Write-Host "    ??  $p answered 200 to an empty body (unexpected)" -ForegroundColor Yellow
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 401) { Ok "$p -> 401 without credentials (published)" }
        elseif ($code -eq 404) { Write-Host "    ERR $p -> 404: workflow NOT published" -ForegroundColor Red }
        else { Write-Host "    ??  $p -> $code" -ForegroundColor Yellow }
    }
}

# --- 6. Summary ------------------------------------------------------------------
Write-Host ""
Write-Host "=================== READY FOR DEMO ===================" -ForegroundColor Green
Write-Host "Public URL:  $url"
Write-Host ""
Write-Host "Paste into ElevenLabs (tools + Settings > Post-call webhook):"
foreach ($p in "get-ultima-bolletta", "invia-autolettura", "apri-ticket", "post-call") {
    Write-Host "  $url/webhook/$p"
}
Write-Host ""
Write-Host "n8n editor:  http://localhost:$port"
Write-Host "Keep this window open. Ctrl+C stops the tunnel." -ForegroundColor Yellow
Write-Host "======================================================" -ForegroundColor Green

if ($NoWait) { exit 0 }
try { Wait-Process -Id $tunnel.Id } finally {
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "`nTunnel stopped."
}
