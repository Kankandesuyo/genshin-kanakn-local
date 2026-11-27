# Shared settings for all local-server scripts.
# Per-machine settings live in local-config.json (created by setup-local.ps1, not tracked by git).
$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Read-PlainPassword([string]$prompt) {
    $secure = Read-Host $prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Test-GamePassword([string]$password) {
    # The password is sent as one console-command argument, so it cannot contain whitespace.
    if ($password.Length -lt 6 -or $password -match '\s') { throw 'Password must be at least 6 characters with no spaces.' }
}

function Get-LocalConfig {
    $path = Join-Path $script:RepoRoot 'local-config.json'
    $cfg = [ordered]@{ java = ''; clientPath = ''; directInterface = ''; cdnIp = '' }
    if (Test-Path $path) {
        $file = Get-Content $path -Raw | ConvertFrom-Json
        foreach ($p in $file.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    }
    if (!$cfg.clientPath) { $cfg.clientPath = Join-Path $script:RepoRoot 'client-7.2' }
    if (!$cfg.java) {
        $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($cmd) { $cfg.java = $cmd.Source }
    }
    [pscustomobject]$cfg
}
