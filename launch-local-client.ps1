$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
$cfg = Get-LocalConfig
$client = $cfg.clientPath
$receiptPath = "$root\logs\client-patch-install.json"
if (!(Test-Path $receiptPath)) { throw 'Local client patch is not installed yet.' }
$receipt = Get-Content $receiptPath -Raw | ConvertFrom-Json
if ($receipt.state -ne 'installed') { throw 'Local client patch is not active.' }
$patch = Join-Path $client $receipt.patchRelativePath
if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash -ne $receipt.patchSha256) { throw 'Local patch checksum changed.' }
foreach ($package in @('game','zh-cn')) {
    $progressPath = Join-Path $client "download-progress-$package.json"
    if (!(Test-Path $progressPath)) { throw "Package $package has not downloaded yet. Open Download-Status.cmd." }
    $progress = Get-Content $progressPath -Raw | ConvertFrom-Json
    if ($progress.state -ne 'completed') { throw "Package $package is still downloading. Open Download-Status.cmd." }
}
if (!(Get-NetTCPConnection -LocalPort 8088 -State Listen -ErrorAction SilentlyContinue)) {
    & "$root\start-local.ps1"
}
$ready = $false
foreach ($attempt in 1..360) {
    try {
        $status = Invoke-RestMethod 'http://127.0.0.1:8088/api/status' -TimeoutSec 2
        if ($status.retcode -eq 0) { $ready = $true; break }
    } catch { }
    if ($attempt -eq 1) { Write-Host 'Waiting for the local server to finish loading resources...' }
    Start-Sleep -Seconds 1
}
if (!$ready) { throw 'Local server is not ready. Check server/logs/latest.log.' }
if (Get-Process GenshinImpact -ErrorAction SilentlyContinue) { throw 'Genshin is already running. Close it before launching this copy.' }
$env:LUNAGC_PATCH_LOG = "$root\logs\client-patch.log"
$env:HTTP_PROXY = ''
$env:HTTPS_PROXY = ''
$env:ALL_PROXY = ''
$env:NO_PROXY = 'localhost,127.0.0.1'
$gameProcess = Start-Process -FilePath "$client\GenshinImpact.exe" -WorkingDirectory $client -WindowStyle Normal -PassThru
$gameProcess.Id | Set-Content "$root\logs\client-game.pid"
Write-Host 'Local 7.1 client launched. Use your local player account, not a HoYoverse account.'
