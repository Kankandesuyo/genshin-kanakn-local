param([string]$ClientPath, [switch]$SkipAccount)
# One-time setup on a new machine: downloads runtime pieces from their original sources,
# generates fresh local passwords, and creates the local game account. Re-running is safe.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
foreach ($dir in @('logs','db','runtime\downloads')) { New-Item -ItemType Directory -Force "$root\$dir" | Out-Null }
$downloads = "$root\runtime\downloads"

$repo = 'Kankandesuyo/genshin-kanakn-local'
$releaseTag = 'v1.0.0'
$assets = @(
    @{ name='grasscutter.jar'; target="$root\server\grasscutter.jar"; sha='40D32550A7FB823A5089BC931D6644895BE8E8D3AF4385DD96A285D13BCF7DC1' },
    @{ name='LocalStatueCompat.jar'; target="$root\server\plugins\LocalStatueCompat.jar"; sha='633082596FFEFA6DF04811C921C8F5761952FB590F607D5D77E6A8CC40CC5C26' },
    @{ name='Astrolabe-local-patch.dll'; target="$root\runtime\patch\Astrolabe-local-patch.dll"; sha='6D64CE888305924127FCE46458F86C3DD58D344A3B5B01C2A23E8D500FF4F63C' },
    @{ name='Sophon.Downloader-win-x64.zip'; target="$downloads\Sophon.Downloader-win-x64.zip"; sha='93C31BD06B3A8141510F6E08A8C7F8FF55364114FEA339B22F67292E3C1915B1' }
)
$mongoUrl = 'https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-8.0.12.zip'
# Server resources are pinned to the upstream commit this setup was tested with.
$resourceCommit = 'c0213668889ed05cbeb86660f424c3daf18bfacd'
$resourceUrl = "https://github.com/MeChen618/AstaPS-Resource/archive/$resourceCommit.zip"

function Get-File([string]$url, [string]$target, [string]$sha) {
    if ((Test-Path $target) -and (!$sha -or (Get-FileHash $target -Algorithm SHA256).Hash -eq $sha)) { Write-Host "  ok: $(Split-Path $target -Leaf)"; return }
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Write-Host "  downloading $url"
    Invoke-WebRequest -Uri $url -OutFile "$target.part" -UseBasicParsing
    if ($sha -and (Get-FileHash "$target.part" -Algorithm SHA256).Hash -ne $sha) { Remove-Item "$target.part"; throw "SHA256 mismatch: $url" }
    Move-Item -Force "$target.part" $target
}
function New-Secret([int]$length = 20) {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $bytes = New-Object byte[] $length
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

Write-Host '[1/6] Local settings'
$configPath = "$root\local-config.json"
if (!(Test-Path $configPath)) {
    if (!$ClientPath) {
        $default = Join-Path $root 'client-7.1'
        $ClientPath = Read-Host "Game client folder (needs ~150 GB free) [$default]"
        if (!$ClientPath) { $ClientPath = $default }
    }
    $cfg = Get-Content "$root\config\local-config.example.json" -Raw | ConvertFrom-Json
    $cfg.clientPath = $ClientPath
    $cfg | ConvertTo-Json | Set-Content -Encoding UTF8 $configPath
}
$cfg = Get-LocalConfig
Write-Host "  client folder: $($cfg.clientPath)"

Write-Host '[2/6] Java 17+'
if (!$cfg.java -or !(Test-Path $cfg.java)) { throw 'Java not found. Install Java 17 or newer (https://adoptium.net/) or set "java" in local-config.json.' }
$versionLine = (& cmd.exe /d /c "`"$($cfg.java)`" -version 2>&1" | Select-Object -First 1)
if ($versionLine -match '"(\d+)' -and [int]$matches[1] -lt 17) { throw "Java 17+ required, found: $versionLine" }
Write-Host "  $versionLine"

Write-Host '[3/6] Release files (server jar, plugin, client patch, downloader)'
foreach ($a in $assets) { Get-File "https://github.com/$repo/releases/download/$releaseTag/$($a.name)" $a.target $a.sha }
if (!(Test-Path "$root\runtime\sophon\Sophon.Downloader.exe")) { Expand-Archive -Force "$downloads\Sophon.Downloader-win-x64.zip" "$root\runtime\sophon" }

Write-Host '[4/6] MongoDB 8.0.12 (local only, not installed as a service)'
if (!(Get-ChildItem "$root\runtime" -Filter mongod.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    Get-File $mongoUrl "$downloads\mongodb.zip" $null
    Expand-Archive -Force "$downloads\mongodb.zip" "$root\runtime\mongodb"
}

Write-Host '[5/6] Server resources (MeChen618/AstaPS-Resource)'
if (!(Test-Path "$root\server\resources\ExcelBinOutput")) {
    Get-File $resourceUrl "$downloads\astaps-resources.zip" $null
    $tmp = "$downloads\resources-extract"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Force "$downloads\astaps-resources.zip" $tmp
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (Test-Path "$root\server\resources") { Remove-Item -Recurse -Force "$root\server\resources" }
    Move-Item $inner.FullName "$root\server\resources"
    Remove-Item -Recurse -Force $tmp
}

Write-Host '[6/6] Passwords and local account'
$credPath = "$root\credentials.local.json"
if (!(Test-Path $credPath)) {
    @{ playerUsername='player'; playerPassword=(New-Secret); consolePassword=(New-Secret 24) } | ConvertTo-Json | Set-Content -Encoding UTF8 $credPath
}
$cred = Get-Content $credPath -Raw | ConvertFrom-Json
if (!(Test-Path "$root\server\config.json")) {
    $serverCfg = Get-Content "$root\server\config.example.json" -Raw | ConvertFrom-Json
    $serverCfg.server.http.webConsole.password = $cred.consolePassword
    $serverCfg | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 "$root\server\config.json"
}
if (!$SkipAccount -and !(Test-Path "$root\logs\account-created.flag")) {
    & "$root\start-local.ps1"
    Write-Host '  waiting for the server to load resources (first start can take ~5 minutes)...'
    $ready = $false
    foreach ($i in 1..600) {
        try { if ((Invoke-RestMethod 'http://127.0.0.1:8088/api/status' -TimeoutSec 2).retcode -eq 0) { $ready = $true; break } } catch { }
        Start-Sleep -Seconds 1
    }
    if (!$ready) { throw 'Server did not become ready. Check server/logs/latest.log, then rerun Setup.cmd.' }
    & "$root\console-command.ps1" -Command "account create $($cred.playerUsername) $($cred.playerPassword) @10001" | Out-Host
    Get-Date -Format o | Set-Content "$root\logs\account-created.flag"
}
Write-Host ''
Write-Host 'Setup done. Passwords are in credentials.local.json (never share this file).'
Write-Host 'Next: Download-Client.cmd (official HoYoverse CDN), then Install-Patch.cmd, then Play-Local.cmd.'
