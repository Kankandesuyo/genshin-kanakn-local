param([switch]$Check,[switch]$CheckOnline)
& "$PSScriptRoot/runtime/Local-Manager-v2.ps1" -Check:$Check -CheckOnline:$CheckOnline
