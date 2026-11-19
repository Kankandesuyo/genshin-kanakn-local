$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot/Manager-GearUI.ps1",[ref]$tokens,[ref]$errors)
if($errors.Count){throw $errors[0]}
foreach($name in @('Invoke-GearUpgradeBatch','Get-CheckedGearRequests')){$node=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true);Invoke-Expression $node.Extent.Text}
$status=New-Object Windows.Forms.Label
$ownedAvatar=New-Object Windows.Forms.CheckedListBox;$ownedWeapon=New-Object Windows.Forms.CheckedListBox
$script:avatarUpgradeRows=@(@{id=1;level=1;promote=0;maxLevel=90;maxPromote=6},@{id=2;level=1;promote=0;maxLevel=90;maxPromote=6})
$script:weaponUpgradeRows=@(@{guid='9007199254740993';level=1;promote=0;maxLevel=90;maxPromote=6},@{guid='9007199254740995';level=90;promote=6;maxLevel=90;maxPromote=6},@{guid='9007199254740997';level=1;promote=0;maxLevel=90;maxPromote=6},@{guid='9007199254740999';level=1;promote=0;maxLevel=90;maxPromote=6})
$null=$ownedAvatar.Items.Add('unselected');$null=$ownedAvatar.Items.Add('selected avatar');$ownedAvatar.SetItemChecked(1,$true)
foreach($row in $script:weaponUpgradeRows){$null=$ownedWeapon.Items.Add($row.guid)};for($i=0;$i -lt 4;$i++){$ownedWeapon.SetItemChecked($i,$true)}
$requests=@(Get-CheckedGearRequests);if($requests.Count -ne 5 -or $requests[0].id -ne 2 -or $requests[1].guid -cne '9007199254740993'){throw 'Checkbox targeting or GUID precision failed'}
$script:calls=@();function Invoke-LocalGearAction($action,$payload){$script:calls+=$payload;if($payload.guid -eq '9007199254740997'){throw 'simulated server failure'};@{ok=$true;level=90;promote=6}}
$result=@(Invoke-GearUpgradeBatch $requests)
if($script:calls.Count -ne 4 -or @($result|Where-Object state -eq 'success').Count -ne 3 -or @($result|Where-Object state -eq 'skipped').Count -ne 1 -or @($result|Where-Object state -eq 'failed').Count -ne 1 -or $result[-1].state -ne 'success'){throw 'Partial failure/skip handling failed'}
if(@($script:calls|Where-Object id -eq 1).Count){throw 'Unchecked avatar changed'}
$ownedAvatar.Dispose();$ownedWeapon.Dispose();$status.Dispose()
'PASS: mixed checked selection, unchecked exclusion, exact large GUID, full-level skip and continued processing after failure. Mock commands only; no game data changed.'
$script:talentCalls=@();function Invoke-LocalGearAction($action,$payload){if($action -ne 'talents'){throw 'Wrong command'};$script:talentCalls+=$payload;@{ok=$true;count=3}}
$request=@{type='avatar';id=2;name='max-level avatar';level=90;maxLevel=90;promote=6;maxPromote=6}
$result=@(Invoke-GearUpgradeBatch @($request) 'talents')
if($script:talentCalls.Count -ne 1 -or $script:talentCalls[0].id -ne 2 -or $result[0].state -ne 'success'){throw 'Talent batch incorrectly skipped full-level avatar'}
'PASS: full-level character still receives talent action; explicit avatar id preserved. Mock only.'