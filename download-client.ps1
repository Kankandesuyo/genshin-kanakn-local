$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
$cfg = Get-LocalConfig
$destination = $cfg.clientPath
$exe = "$root\runtime\sophon\Sophon.Downloader.exe"
if (!(Test-Path $exe)) { $exe = "$root\runtime\SophonDownloader-master\Sophon.Downloader\Core\bin\Release\net9.0\Sophon.Downloader.exe" }
if (!(Test-Path $exe)) { throw 'Sophon.Downloader.exe missing. Run Setup.cmd first.' }
$statePath = "$root\logs\client-download-state.json"
if (Test-Path "$root\logs\client-worker.pid") {
    $oldWorker = Get-Process -Id ([int](Get-Content "$root\logs\client-worker.pid")) -ErrorAction SilentlyContinue
    if ($oldWorker -and $oldWorker.Path -eq $exe) { throw 'The client downloader is already running.' }
}
New-Item -ItemType Directory -Force $destination | Out-Null
function Save-State([string]$state,[string]$stage,[string]$message) {
    @{state=$state;stage=$stage;message=$message;destination=$destination;updatedAt=(Get-Date -Format o)} |
        ConvertTo-Json | Set-Content -Encoding UTF8 $statePath
}
$PID | Set-Content "$root\logs\client-supervisor.pid"
try {
    $build = Get-Content "$root\manifests\official-sophon-build.json" -Raw | ConvertFrom-Json
    $branch = Get-Content "$root\manifests\official-game-branches.json" -Raw | ConvertFrom-Json
    if ($build.data.tag -ne '7.1.0' -or $branch.data.game_branches[0].main.tag -ne '7.1.0') { throw 'Expected pinned 7.1.0 official manifests.' }
    $requiredBytes = ($build.data.manifests | Where-Object matching_field -in @('game','zh-cn') | ForEach-Object {[long]$_.stats.uncompressed_size} | Measure-Object -Sum).Sum
    $freeBytes = (Get-PSDrive (Split-Path -Qualifier (Resolve-Path $destination)).TrimEnd(':')).Free
    if ($freeBytes -lt ($requiredBytes + 10GB) -and !(Test-Path "$destination\download-progress-game.json")) { throw "Not enough free space for $destination (needs about 150 GB)." }
    $env:NO_PROXY = '*'
    # Optional: pin download sockets to one network adapter (e.g. "WLAN") to bypass a TUN/VPN route.
    if ($cfg.directInterface) {
        $physical = Get-NetIPConfiguration -InterfaceAlias $cfg.directInterface
        if (!$physical.IPv4Address.IPAddress -or !$physical.IPv4DefaultGateway) { throw "$($cfg.directInterface) is not connected." }
        $env:SOPHON_DIRECT_INTERFACE = [string]$physical.InterfaceIndex
        $env:SOPHON_DIRECT_ADDRESS = [string]$physical.IPv4Address.IPAddress
    }
    $env:HTTP_PROXY = ''
    $env:HTTPS_PROXY = ''
    $env:ALL_PROXY = ''
    $env:SOPHON_BRANCH_JSON = "$root\manifests\official-game-branches.json"
    $env:SOPHON_BUILD_JSON = "$root\manifests\official-sophon-build.json"
    foreach ($package in @('game','zh-cn')) {
        $existingProgress = "$destination\download-progress-$package.json"
        if (Test-Path $existingProgress) {
            $finished = Get-Content $existingProgress -Raw | ConvertFrom-Json
            if ($finished.state -eq 'completed' -and $finished.completedFiles -eq $finished.totalFiles -and $finished.bytesWritten -eq $finished.totalBytes) { continue }
        }
        $success = $false
        foreach ($attempt in 1..3) {
            Save-State 'downloading' $package "Attempt $attempt of 3. Files use official HoYoverse CDN."
            # Optional: force an official CDN IP (only if DNS for autopatchhk.yuanshen.com is broken).
            if ($cfg.cdnIp) { $env:SOPHON_CDN_IP = $cfg.cdnIp }
            $args = @('full','hk4e',$package,'7.1.0',$destination,'--silent','--threads=24','--handles=32')
            $process = Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput "$root\logs\client-$package.stdout.log" -RedirectStandardError "$root\logs\client-$package.stderr.log" -PassThru
            $process.Id | Set-Content "$root\logs\client-worker.pid"
            $process.WaitForExit()
            $process.Refresh()
            $progressPath = "$destination\download-progress-$package.json"
            # Windows PowerShell can expose a null ExitCode after WaitForExit/Refresh.
            # The completed manifest is written only after all file MD5 checks pass.
            if (($null -eq $process.ExitCode -or $process.ExitCode -eq 0) -and (Test-Path $progressPath)) {
                $progress = Get-Content $progressPath -Raw | ConvertFrom-Json
                if ($progress.state -eq 'completed') { $success = $true; break }
            }
            if ($attempt -lt 3) { Start-Sleep -Seconds 10 }
        }
        if (!$success) { throw "Download stage $package failed after retries. See logs/client-$package.stderr.log. Rerunning skips files whose MD5 matches." }
    }
    Save-State 'completed' 'all' 'Game and Chinese audio downloaded and file MD5 checks passed.'
} catch {
    Save-State 'failed' 'download' $_.Exception.Message
    throw
}
