param([string]$ClientPath, [string]$Username, [string]$Password, [switch]$SkipAccount)
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
    @{ name='LocalStatueCompat.jar'; target="$root\server\plugins\LocalStatueCompat.jar"; sha='633082596FFEFA6DF04811C921C8F5761952FB590F607D5D77E6A8CC40CC5C26' },
    @{ name='Astrolabe-local-patch.dll'; target="$root\runtime\patch\Astrolabe-local-patch.dll"; sha='6D64CE888305924127FCE46458F86C3DD58D344A3B5B01C2A23E8D500FF4F63C' },
    @{ name='Sophon.Downloader-win-x64.zip'; target="$downloads\Sophon.Downloader-win-x64.zip"; sha='93C31BD06B3A8141510F6E08A8C7F8FF55364114FEA339B22F67292E3C1915B1' }
)
$mongoUrl = 'https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-8.0.12.zip'
# Server resources are pinned to the upstream commit this setup was tested with.
$resourceCommit = 'f2800e32599f32cde76ae0b4b93ea30b75651e59'
$resourceUrl = "https://codeload.github.com/MeChen618/AstaPS-Resource/zip/$resourceCommit"

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
        $default = Join-Path $root 'client-7.2'
        $ClientPath = Read-Host "Game client folder (needs ~150 GB free) [$default]"
        if (!$ClientPath) { $ClientPath = $default }
    }
    $cfg = Get-Content "$root\config\local-config.example.json" -Raw | ConvertFrom-Json
    $cfg.clientPath = $ClientPath
    $cfg | ConvertTo-Json | Set-Content -Encoding UTF8 $configPath
}
$cfg = Get-LocalConfig
Write-Host "  client folder: $($cfg.clientPath)"

Write-Host '[2/6] Java 21+'
if (!$cfg.java -or !(Test-Path $cfg.java)) { throw 'Java not found. Install Java 21 or newer (https://adoptium.net/) or set "java" in local-config.json.' }
$versionLine = (& cmd.exe /d /c "`"$($cfg.java)`" -version 2>&1" | Select-Object -First 1)
if ($versionLine -match '"(\d+)' -and [int]$matches[1] -lt 21) { throw "Java 21+ required, found: $versionLine" }
Write-Host "  $versionLine"

Write-Host '[3/6] Release files (server jar, plugin, client patch, downloader)'
Get-File 'https://github.com/MeChen618/AstaPS/releases/download/7.2.162/grasscutter.jar' "$root/server/grasscutter.jar" '2AB3D86FB2890F271B65E464320B4CAF8E77B7A2DB5F29ABF29E81A1E8892294'
foreach ($a in $assets) { Get-File "https://github.com/$repo/releases/download/$releaseTag/$($a.name)" $a.target $a.sha }
if (!(Test-Path "$root\runtime\sophon\Sophon.Downloader.exe")) { Expand-Archive -Force "$downloads\Sophon.Downloader-win-x64.zip" "$root\runtime\sophon" }

Write-Host '[4/6] MongoDB 8.0.12 (local only, not installed as a service)'
if (!(Get-ChildItem "$root\runtime" -Filter mongod.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    Get-File $mongoUrl "$downloads\mongodb.zip" $null
    Expand-Archive -Force "$downloads\mongodb.zip" "$root\runtime\mongodb"
}

Write-Host '[5/6] Server resources (MeChen618/AstaPS-Resource)'
$resources = Join-Path $root 'server/resources'
$marker = Join-Path $resources '.astaps-resource-version'
if (!(Test-Path "$resources/ExcelBinOutput/AvatarExcelConfigData.json") -or !(Test-Path $marker) -or (Get-Content $marker -Raw).Trim() -ne $resourceCommit) {
    $archive = Join-Path $downloads "resources-$resourceCommit.zip"
    Get-File $resourceUrl $archive 'CBE9D2937AB59D5EF2BB5605D26D255D6D3BDD5B36233471D067FD370431F2FE'
    $stage = Join-Path $downloads ('resources-' + [Guid]::NewGuid())
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $stage)
    $source = Join-Path $stage "AstaPS-Resource-$resourceCommit"
    if (!(Test-Path "$source/ExcelBinOutput/AvatarExcelConfigData.json")) { throw 'Resource archive is incomplete.' }
    robocopy $source $resources /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Resource installation failed (robocopy $LASTEXITCODE)." }
    Set-Content -LiteralPath $marker -Value $resourceCommit -Encoding ASCII
    [IO.Directory]::Delete($stage, $true)
}

Write-Host '[6/6] Passwords and local account'
$credPath = "$root\credentials.local.json"
if (!(Test-Path $credPath)) {
    if (!$Username) {
        $Username = Read-Host 'Game username (letters/digits/_, Enter = player)'
        if (!$Username) { $Username = 'player' }
    }
    if ($Username -notmatch '^[A-Za-z0-9_]{3,20}$') { throw 'Username must be 3-20 letters, digits or _.' }
    if (!$Password) {
        while ($true) {
            $p1 = Read-PlainPassword 'Game password (6+ chars, no spaces, Enter = random)'
            if (!$p1) { $Password = New-Secret; Write-Host '  random password generated (see credentials.local.json)'; break }
            $p2 = Read-PlainPassword 'Repeat password'
            if ($p1 -ne $p2) { Write-Host '  passwords do not match, try again'; continue }
            $Password = $p1; break
        }
    }
    Test-GamePassword $Password
    @{ playerUsername=$Username; playerPassword=$Password; consolePassword=(New-Secret 24) } | ConvertTo-Json | Set-Content -Encoding UTF8 $credPath
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
