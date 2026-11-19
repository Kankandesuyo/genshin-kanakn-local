# Shared settings for all local-server scripts.
# Per-machine settings live in local-config.json (created by setup-local.ps1, not tracked by git).
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalConfig {
    $path = Join-Path $script:RepoRoot 'local-config.json'
    $cfg = [ordered]@{ java = ''; clientPath = ''; directInterface = ''; cdnIp = '' }
    if (Test-Path $path) {
        $file = Get-Content $path -Raw | ConvertFrom-Json
        foreach ($p in $file.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    }
    if (!$cfg.clientPath) { $cfg.clientPath = Join-Path $script:RepoRoot 'client-7.1' }
    if (!$cfg.java) {
        $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($cmd) { $cfg.java = $cmd.Source }
    }
    [pscustomobject]$cfg
}
