$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
# Use the authenticated server shutdown command to flush player data first.
$listener = Get-NetTCPConnection -LocalPort 8088 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    $secrets = Get-Content "$root\credentials.local.json" -Raw | ConvertFrom-Json
    $login = Invoke-RestMethod -Uri 'http://127.0.0.1:8088/console/api/login' -Method Post -ContentType 'application/json' -Body (@{password=$secrets.consolePassword} | ConvertTo-Json)
    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:8088/console/api/command' -Method Post -ContentType 'application/json' -Headers @{'X-Console-Token'=$login.token} -Body '{"command":"stop"}' | Out-Null
    } catch { Write-Host 'Shutdown requested; checking process.' }
}
if (Test-Path "$root\logs\server.pid") {
    $serverPid = [int](Get-Content "$root\logs\server.pid")
    $proc = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if ($proc) {
        Wait-Process -Id $serverPid -Timeout 45 -ErrorAction SilentlyContinue
        if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) { throw 'Server still running. Check logs; database left running to protect saves.' }
    }
}
# MongoDB stays running so its database can close safely on Windows shutdown.
Write-Host 'Game server stopped. Local MongoDB remains available on 127.0.0.1:27018.'
