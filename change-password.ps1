param([string]$Password)
# Change the local game account password. The server must be set up (Setup.cmd) first.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
$credPath = "$root\credentials.local.json"
if (!(Test-Path $credPath)) { throw 'Not set up yet. Run Setup.cmd first.' }
$cred = Get-Content $credPath -Raw | ConvertFrom-Json
Write-Host "Account: $($cred.playerUsername)"
if (!$Password) {
    $Password = Read-PlainPassword 'New password (6+ chars, no spaces)'
    if ($Password -ne (Read-PlainPassword 'Repeat new password')) { throw 'Passwords do not match.' }
}
Test-GamePassword $Password

if (!(Get-NetTCPConnection -LocalPort 8088 -State Listen -ErrorAction SilentlyContinue)) { & "$root\start-local.ps1" }
Write-Host 'Waiting for the local server...'
$ready = $false
foreach ($i in 1..600) {
    try { if ((Invoke-RestMethod 'http://127.0.0.1:8088/api/status' -TimeoutSec 2).retcode -eq 0) { $ready = $true; break } } catch { }
    Start-Sleep -Seconds 1
}
if (!$ready) { throw 'Server is not ready. Check server/logs/latest.log.' }
$result = & "$root\console-command.ps1" -Command "account resetpassword $($cred.playerUsername)@ $Password"
$result | Out-Host
if (($result | Out-String) -notmatch 'Password Updated') { throw 'Password was not changed; see the message above.' }
$cred.playerPassword = $Password
$cred | ConvertTo-Json | Set-Content -Encoding UTF8 $credPath
Write-Host 'Password changed and saved to credentials.local.json.'
