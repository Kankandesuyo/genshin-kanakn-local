$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot/Manager-WeaponCleanup.ps1",[ref]$tokens,[ref]$errors);if($errors.Count){throw $errors[0]}
$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-WeaponCleanupRequest'},$true);Invoke-Expression $node.Extent.Text
$list=New-Object Windows.Forms.CheckedListBox
$script:warehouseRows=@(@{guid='9007199254740993';protected=$false},@{guid='9007199254740995';protected=$true},@{guid='9007199254740997';protected=$false})
foreach($row in $script:warehouseRows){$null=$list.Items.Add($row.guid)};$list.SetItemChecked(0,$true);$list.SetItemChecked(1,$true)
$script:threeRows=@(@{guid='30';protected=$false},@{guid='31';protected=$true})
$r=Get-WeaponCleanupRequest 4;if($r.guids.Count -ne 1 -or $r.guids[0] -cne '9007199254740993'){throw 'Four-star selection/protection/GUID failed'}
$r=Get-WeaponCleanupRequest 3;if($r.guids.Count -ne 1 -or $r.guids[0] -ne '30'){throw 'Three-star protection failed'}
$list.Dispose();'PASS cleanup selection: checked only, protected excluded, exact GUID; three-star unlocked only. No deletion commands executed.'