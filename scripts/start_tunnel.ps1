# Starts a Cloudflare quick tunnel to the local n8n and prints the public URL.
# The URL changes on every start: update the ElevenLabs tool URLs and N8N_WEBHOOK_URL in .env.
# Stop it by closing this window (Ctrl+C). Keep it running only during the demo.
$port = 5679
$exe = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
if (-not (Test-Path $exe)) { $exe = "cloudflared" }   # fall back to PATH
Write-Host "Starting quick tunnel to http://localhost:$port ..."
& $exe tunnel --url "http://localhost:$port" --no-autoupdate 2>&1 | ForEach-Object {
    if ($_ -match "https://[a-z0-9-]+\.trycloudflare\.com") {
        Write-Host "`n==> Public URL: $($Matches[0])" -ForegroundColor Green
        Write-Host "==> Webhook base: $($Matches[0])/webhook/`n"
    }
    $_
}
