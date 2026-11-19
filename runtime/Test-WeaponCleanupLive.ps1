$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Invoke-CleanupLiveCommand($action,$payload=$null){
    $command="localgear $action"
    if($null -ne $payload){$command+=' '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 7 -Compress)))}
    $r=& "$root/console-command.ps1" -Command "$command @10001"
    return ($r.output -join "`n")
}
$status=& "$root/console-command.ps1" -Command 'localgm status @10001'
$ore=(($status.output -join "`n")|ConvertFrom-Json).item104013
if($ore -ne 99999){throw 'This regression requires already full ore; refusing to change existing materials'}
$before=Invoke-CleanupLiveCommand 'list'|ConvertFrom-Json
$receipts=@()
foreach($spec in @(@{id=11301;rank=3},@{id=11401;rank=4})){
    $snapshot=Invoke-CleanupLiveCommand 'list'|ConvertFrom-Json
    $null=& "$root/console-command.ps1" -Command "give $($spec.id) --amount=1 --level=1 @10001"
    $current=Invoke-CleanupLiveCommand 'list'|ConvertFrom-Json
    $created=@($current.weapons|Where-Object {$_.guid -notin $snapshot.weapons.guid -and $_.id -eq $spec.id})
    if($created.Count -ne 1){throw 'Temporary weapon identity ambiguous; no batch deletion attempted'}
    $request=@{rank=$spec.rank;guids=@([string]$created[0].guid)}
    $preview=Invoke-CleanupLiveCommand 'recyclecheck' $request|ConvertFrom-Json
    $expected=if($spec.rank -eq 3){3}else{10}
    if($preview.reward -ne 0 -or $preview.overflow -ne $expected){throw 'Full-capacity preview incorrect'}
    $rejected=Invoke-CleanupLiveCommand 'recyclebatch' $request
    if($rejected -notmatch '^ERROR:'){throw 'Missing overflow consent accepted'}
    $request.allowOverflow=$true;$request.maxOverflow=[int]$preview.overflow
    $result=Invoke-CleanupLiveCommand 'recyclebatch' $request|ConvertFrom-Json
    $after=Invoke-CleanupLiveCommand 'list'|ConvertFrom-Json
    if(!$result.ok -or $result.removed -ne 1 -or $result.overflow -ne $expected -or $created[0].guid -in $after.weapons.guid){throw 'Temporary weapon deletion/readback failed'}
    foreach($item in $before.weapons){if($item.guid -notin $after.weapons.guid){throw 'Original weapon missing'}}
    $receipts+=@{rank=$spec.rank;temporaryGuid=$created[0].guid;preview=$preview;result=$result;originalWeaponsPreserved=$true}
}
$status=& "$root/console-command.ps1" -Command 'localgm status @10001'
if((($status.output -join "`n")|ConvertFrom-Json).item104013 -ne $ore){throw 'Existing ore changed'}
$receipts|ConvertTo-Json -Depth 8|Set-Content "$root/logs/weapon-cleanup-full-ore-live-verification.json" -Encoding UTF8
'PASS: new temporary 3-star and 4-star weapons removed with confirmed overflow; missing confirmation rejected; all original weapons and 99999 ore preserved.'
