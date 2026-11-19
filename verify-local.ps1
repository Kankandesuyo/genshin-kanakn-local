$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:8088'
$secrets = Get-Content "$PSScriptRoot\credentials.local.json" -Raw | ConvertFrom-Json
$status = Invoke-RestMethod "$base/api/status"
$console = Invoke-WebRequest "$base/console" -UseBasicParsing
if ($console.StatusCode -ne 200) { throw 'Console is unavailable' }
try {
    Invoke-RestMethod "$base/console/api/players" | Out-Null
    throw 'Console accepted an anonymous request'
} catch {
    if (!$_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 401) { throw }
}
$goodBody = @{account=$secrets.playerUsername;password=$secrets.playerPassword;is_crypto=$false} | ConvertTo-Json
$badBody = @{account=$secrets.playerUsername;password='incorrect-local-test-password';is_crypto=$false} | ConvertTo-Json
$good = Invoke-RestMethod "$base/hk4e_global/mdk/shield/api/login" -Method Post -ContentType 'application/json' -Body $goodBody
$bad = Invoke-RestMethod "$base/hk4e_global/mdk/shield/api/login" -Method Post -ContentType 'application/json' -Body $badBody
if ($good.retcode -ne 0) { throw "Correct password rejected: $($good.message)" }
if ($bad.retcode -eq 0) { throw 'Wrong password was accepted' }
$tcp = @(Get-NetTCPConnection -LocalPort 8088,27018 -State Listen)
$udp = @(Get-NetUDPEndpoint -LocalPort 22101)
if ($tcp.Count -lt 2 -or $udp.Count -lt 1) { throw 'Required listeners missing' }
if (@($tcp + $udp | Where-Object {
    $address = [Net.IPAddress]::Parse($_.LocalAddress)
    if ($address.IsIPv4MappedToIPv6) { $address = $address.MapToIPv4() }
    ![Net.IPAddress]::IsLoopback($address)
}).Count -gt 0) { throw 'A listener is not restricted to localhost' }
$result = [ordered]@{
    checkedAt=(Get-Date -Format o)
    serverStatus=$status
    consoleHttpStatus=$console.StatusCode
    anonymousConsoleDenied=$true
    correctPasswordAccepted=$true
    wrongPasswordDenied=$true
    allListenersLoopbackOnly=$true
    clientGameplayVerified=$false
}
$result | ConvertTo-Json -Depth 15 | Set-Content "$PSScriptRoot\logs\verification.json" -Encoding UTF8
Write-Host 'PASS: server, database, UDP, console authentication and account password checks.'
Write-Host 'Client gameplay has not been verified.'
