$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (Get-Process GenshinImpact -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
. "$root\runtime\Common.ps1"
$cfg = Get-LocalConfig
$receiptPath = "$root\logs\client-patch-install.json"
$receipt = Get-Content $receiptPath -Raw | ConvertFrom-Json
$target = Join-Path $cfg.clientPath $receipt.patchRelativePath
if ((Get-FileHash -LiteralPath $receipt.backupPath).Hash -ne $receipt.originalSha256) { throw 'Original backup checksum mismatch.' }
if ((Get-FileHash -LiteralPath $target).Hash -ne $receipt.patchSha256) { throw 'Current DLL was changed elsewhere; restore stopped.' }
Copy-Item -LiteralPath $receipt.backupPath -Destination $target
$receipt.state = 'restored'
$receipt | ConvertTo-Json | Set-Content -Encoding UTF8 $receiptPath
Write-Host 'Original plugin restored. The local-game shortcut is now disabled until the patch is reinstalled.'
