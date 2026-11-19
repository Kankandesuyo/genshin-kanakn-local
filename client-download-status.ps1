param([switch]$Watch)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$samples = @{}
do {
if ($Watch) {
    Clear-Host
    $Host.UI.RawUI.WindowTitle = 'Genshin 7.1 download progress'
    Write-Host 'Auto refresh: every 3 seconds. Closing this window does not stop the download.'
    Write-Host ''
}
if (!(Test-Path "$root\logs\client-download-state.json")) { Write-Host 'No download started yet. Run Download-Client.cmd.'; if ($Watch) { Start-Sleep -Seconds 3; continue } else { break } }
$state = Get-Content "$root\logs\client-download-state.json" -Raw | ConvertFrom-Json
Write-Host "State: $($state.state); stage: $($state.stage)"
Write-Host "Folder: $($state.destination)"
foreach ($package in @('game','zh-cn')) {
    $path = Join-Path $state.destination "download-progress-$package.json"
    if (Test-Path $path) {
        $data = Get-Content $path -Raw | ConvertFrom-Json
        $percent = if ($data.totalBytes -gt 0) {100 * $data.bytesWritten / $data.totalBytes} else {0}
        Write-Host ('{0}: {1:N2}% | {2:N2}/{3:N2} GiB | files {4}/{5}' -f $package,$percent,($data.bytesWritten/1GB),($data.totalBytes/1GB),$data.completedFiles,$data.totalFiles)
        if ($Watch) {
            $point = @{time=[datetimeoffset]$data.updatedAt;bytes=[double]$data.bytesWritten}
            if (!$samples.ContainsKey($package) -or ($samples[$package].Count -gt 0 -and $point.bytes -lt $samples[$package][-1].bytes)) { $samples[$package] = @() }
            if ($samples[$package].Count -eq 0 -or $point.time -gt $samples[$package][-1].time) {
                $samples[$package] = @($samples[$package] + $point | Select-Object -Last 6)
            }
            if ($samples[$package].Count -ge 2) {
                $first=$samples[$package][0]
                $seconds=($point.time-$first.time).TotalSeconds
                if ($seconds -gt 0) {
                    $speed=($point.bytes-$first.bytes)/$seconds
                    if (([datetimeoffset]::Now-$point.time).TotalSeconds -gt 15) { $speed=0 }
                    Write-Host ('  Recent speed: {0:N2} MiB/s' -f ($speed/1MB))
                    if ($speed -gt 0 -and $data.state -eq 'downloading') {
                        $minutes=($data.totalBytes-$data.bytesWritten)/$speed/60
                        Write-Host ('  Estimated remaining for this package: {0:N0} minutes' -f $minutes)
                    }
                }
            }
        }
    }
}
Write-Host $state.message
if ($Watch) { Start-Sleep -Seconds 3 }
} while ($Watch)
