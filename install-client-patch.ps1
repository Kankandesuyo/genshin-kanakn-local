$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
$cfg = Get-LocalConfig
$client = $cfg.clientPath
$patch = "$root\runtime\patch\Astrolabe-local-patch.dll"
$patchSha = '6D64CE888305924127FCE46458F86C3DD58D344A3B5B01C2A23E8D500FF4F63C'
$originalSha = '0DD661D0DE22B41FCE97E8FBBC8B4128B070E083581EE3320A851F502ECC61DD'  # official 7.2.0 Astrolabe.dll
$relative = 'GenshinImpact_Data\Plugins\Astrolabe.dll'
$target = Join-Path $client $relative
$backup = "$root\client-backup\7.2.0\Astrolabe.dll"
$receiptPath = "$root\logs\client-patch-install.json"

if (Get-Process GenshinImpact -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
if (!(Test-Path $patch) -or (Get-FileHash $patch).Hash -ne $patchSha) { throw 'Patch DLL missing or changed. Run Setup.cmd first.' }
if (!(Test-Path $target)) { throw "Client not found at $target. Finish Download-Client.cmd first." }
$current = (Get-FileHash $target).Hash
if ($current -eq $patchSha) {
    if (!(Test-Path $backup) -or (Get-FileHash $backup).Hash -ne $originalSha) { throw 'Run Download-Client.cmd first to verify the original 7.2 client.' }
    Write-Host 'Patch already installed.'
}
else {
    if ($current -ne $originalSha) { throw 'Client Astrolabe.dll is not the official 7.2.0 file; patch not installed.' }
    New-Item -ItemType Directory -Force (Split-Path $backup), "$root\logs" | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Force
    Copy-Item -LiteralPath $target -Destination (Join-Path $client 'Astrolabe_orig.dll') -Force
    Copy-Item -LiteralPath $patch -Destination $target -Force
    Write-Host 'Patch installed. Original DLL backed up to client-backup\7.2.0.'
}
@{ state='installed'; patchSha256=$patchSha; originalSha256=$originalSha; backupPath=$backup; patchRelativePath=$relative
   dispatchUrl='http://127.0.0.1:8088'; gameVersion='7.2.0'; sourceUrl='https://github.com/capyb2222/animegamepatch'
   installedAt=(Get-Date -Format o) } | ConvertTo-Json | Set-Content -Encoding UTF8 $receiptPath
Write-Host 'Use Play-Local.cmd to start. Restore-Client.cmd puts the official DLL back.'
