$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$catalog=Get-Content "$root/runtime/gear-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
$entry=$catalog.sets|Where-Object id -eq 15045
if($entry.name -ne '天之美赐'){throw 'Set name missing'}
$pieces=@($catalog.items|Where-Object setId -eq 15045)
if($pieces.Count -ne 5){throw 'Incomplete set'}
foreach($piece in $pieces){
    $subs=@();$index=0
    foreach($sub in @($piece.subs|Select-Object -First 4)){$subs+=@{id=[int]$sub.id;count=$(if($index -eq 0){6}else{1})};$index++}
    $request=@{item=[int]$piece.id;level=20;main=[int]$piece.mains[0].id;subs=$subs}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 6 -Compress)))
    $reply=& "$root/console-command.ps1" -Command "localgear validate $encoded @10001"
    $result=($reply.output -join "`n")|ConvertFrom-Json
    if(!$result.ok){throw 'Validation failed'}
    "PASS Celestial Gift: $($piece.slot) id=$($piece.id), validation only"
}
