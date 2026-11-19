param([Parameter(Mandatory=$true)][string]$Command)
$ErrorActionPreference = 'Stop'
$secrets = Get-Content "$PSScriptRoot\credentials.local.json" -Raw | ConvertFrom-Json
$base = 'http://127.0.0.1:8088'
$login = Invoke-RestMethod -Uri "$base/console/api/login" -Method Post -ContentType 'application/json' -Body (@{password=$secrets.consolePassword} | ConvertTo-Json)
try {
    Invoke-RestMethod -Uri "$base/console/api/command" -Method Post -ContentType 'application/json' -Headers @{'X-Console-Token'=$login.token} -Body (@{command=$Command} | ConvertTo-Json)
} finally {
    Invoke-RestMethod -Uri "$base/console/api/logout" -Method Post -Headers @{'X-Console-Token'=$login.token} | Out-Null
}
