$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$catalog=Get-Content "$root/runtime/gear-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
$piece=$catalog.items|Where-Object {$_.slot -eq 'EQUIP_SHOES'}|Select-Object -First 1
$main=$piece.mains|Where-Object prop -eq 'FIGHT_PROP_HP_PERCENT'|Select-Object -First 1
$repeat=$piece.subs|Where-Object prop -eq $main.prop|Select-Object -First 1
if(!$main -or !$repeat){throw 'Matching data missing'}
$others=@($piece.subs|Where-Object prop -ne $main.prop|Select-Object -First 3)
$subs=@(@{id=[int]$repeat.id;count=6});foreach($s in $others){$subs+=@{id=[int]$s.id;count=1}}
$request=@{item=[int]$piece.id;level=20;main=[int]$main.id;subs=$subs}
function Invoke-RelicPreview($request){$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 7 -Compress)));$r=& "$root/console-command.ps1" -Command "localgear validate $encoded @10001";return ($r.output -join "`n")}
$valid=Invoke-RelicPreview $request|ConvertFrom-Json;if(!$valid.ok){throw 'Main/sub repeat rejected'}
$request.subs[1].id=$request.subs[0].id
$invalid=Invoke-RelicPreview $request;if($invalid -notmatch '^ERROR:'){throw 'Duplicate substats accepted'}
@{matchingMainSubAccepted=$true;duplicateSubstatsRejected=$true;createdItems=0}|ConvertTo-Json|Set-Content "$root/logs/artifact-main-sub-repeat-verification.json" -Encoding UTF8
'PASS: main/sub repeat accepted; duplicate substats rejected; validation only, no item created.'