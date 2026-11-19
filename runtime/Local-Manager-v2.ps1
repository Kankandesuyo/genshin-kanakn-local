param([switch]$Check,[switch]$CheckOnline)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=Split-Path $PSScriptRoot -Parent
$catalog=Get-Content "$root/runtime/manager-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
$weaponNames=Get-Content "$root/runtime/weapon-names-zh.json" -Raw -Encoding UTF8|ConvertFrom-Json
function Invoke-LocalGameCommand([string]$Arguments){$r=& "$root/console-command.ps1" -Command "localgm $Arguments @10001";$text=$r.output -join "`n";if($text -notmatch '^\s*\{'){throw $text};$text|ConvertFrom-Json}
function Label($parent,$text,$x,$y,$width=570,$height=30){$c=New-Object Windows.Forms.Label;$c.Text=$text;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,$height);$parent.Controls.Add($c);return $c}
function Button($parent,$text,$x,$y,$width=180){$c=New-Object Windows.Forms.Button;$c.Text=$text;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,36);$parent.Controls.Add($c);return $c}
$form=New-Object Windows.Forms.Form;$form.Text='原神 7.1 本地服管理器';$form.ClientSize=New-Object Drawing.Size(670,630);$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedSingle';$form.MaximizeBox=$false;$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10);$form.BackColor=[Drawing.Color]::FromArgb(245,247,251)
$title=Label $form '原神本地服管理器' 20 14 600 34;$title.Font=New-Object Drawing.Font('Microsoft YaHei UI',17)
$null=Label $form '先进入游戏世界，再读取和修改；填写的是你想拥有的总数量。' 22 52
$play=Button $form '启动游戏' 20 90 190;$refresh=Button $form '读取当前数量' 230 90 190;$console=Button $form '打开控制台' 440 90 190
$tabs=New-Object Windows.Forms.TabControl;$tabs.Location=New-Object Drawing.Point(20,144);$tabs.Size=New-Object Drawing.Size(630,430);$form.Controls.Add($tabs)
$qty=New-Object Windows.Forms.TabPage('数量和材料');$qty.AutoScroll=$true
$banner=New-Object Windows.Forms.TabPage('卡池 UP');$warehouse=New-Object Windows.Forms.TabPage('四星武器仓库');$tabs.TabPages.AddRange(@($qty,$banner,$warehouse))
$status=Label $form '准备就绪，请先进入游戏后读取数量。' 20 588 630
$fields=@(
    @{key='primogems';id=201;label='原石';max=100000000},@{key='mora';id=202;label='摩拉';max=100000000},
    @{key='intertwined';id=223;label='纠缠之缘';max=100000000},@{key='acquaint';id=224;label='相遇之缘';max=100000000},
    @{key='resin';id=106;label='原粹树脂';max=2000},@{key='item104003';id=104003;label='大英雄的经验（紫书）';max=99999},
    @{key='item104002';id=104002;label='冒险家的经验（蓝书）';max=99999},@{key='item104001';id=104001;label='流浪者的经验（绿书）';max=99999},
    @{key='item104013';id=104013;label='精锻用魔矿';max=99999},@{key='item104012';id=104012;label='精锻用良矿';max=99999},@{key='item104011';id=104011;label='精锻用杂矿';max=99999})
$null=Label $qty '填 0 会清零。向下滚动可看到所有材料。' 15 12
$boxes=@{};$labels=@{};$index=0
foreach($field in $fields){$y=52+$index*44;$labels[$field.key]=Label $qty $field.label 18 ($y+3) 220;$n=New-Object Windows.Forms.NumericUpDown;$n.Location=New-Object Drawing.Point(250,$y);$n.Size=New-Object Drawing.Size(250,32);$n.Minimum=0;$n.Maximum=$field.max;$n.ThousandsSeparator=$true;$n.Enabled=$false;$qty.Controls.Add($n);$boxes[$field.key]=$n;$index++}
$apply=Button $qty '应用这些总数量' 20 (60+$index*44) 540;$apply.Enabled=$false
$null=Label $qty '修改后会保存到本地账号；未修改的项目不会重复设置。' 20 (104+$index*44)
$heal=Button $qty '队伍回血／复活' 20 (144+$index*44) 540
$null=Label $banner '角色池五星 UP' 20 35 160;$null=Label $banner '武器池五星 UP' 20 95 160
$character=New-Object Windows.Forms.ComboBox;$character.Location=New-Object Drawing.Point(190,30);$character.Width=360;$character.Items.AddRange([object[]]@($catalog.avatars|Where-Object {$_.stars -eq 5}|ForEach-Object {"$($_.id) $($_.name)"}));$banner.Controls.Add($character)
$weapon=New-Object Windows.Forms.ComboBox;$weapon.Location=New-Object Drawing.Point(190,90);$weapon.Width=360;$weapon.Items.AddRange([object[]]@($catalog.weapons|ForEach-Object {"$($_.id) $($_.name)"}));$banner.Controls.Add($weapon)
$banners=Button $banner '保存卡池 UP' 20 155 540;$null=Label $banner "四类卡池分别统计。`n保存只修改实际 UP；图片沿用兼容模板。" 20 215 550 80
. "$root/runtime/Manager-WeaponCleanup.ps1"
function Failure($problem){$status.Text='操作未完成，请查看提示。';[Windows.Forms.MessageBox]::Show([string]$problem,'操作未完成','OK','Warning')|Out-Null}
function Read-Current {
    $data=Invoke-LocalGameCommand 'status'
    foreach($field in $fields){$value=$data.($field.key);if($null -eq $value){throw '服务端尚未更新，请重新进入游戏。'};$boxes[$field.key].Maximum=[Math]::Max([decimal]$field.max,[decimal]$value);$boxes[$field.key].Value=[decimal]$value;$boxes[$field.key].Enabled=$true}
    $apply.Enabled=$true
    if($data.characterUp.Count){$id=[string]$data.characterUp[0];$match=@($character.Items|Where-Object {$_ -like "$id *"});$character.Text=if($match.Count){$match[0]}else{$id}}
    if($data.weaponUp.Count){$id=[string]$data.weaponUp[0];$match=@($weapon.Items|Where-Object {$_ -like "$id *"});$weapon.Text=if($match.Count){$match[0]}else{$id}}
    $status.Text='已读取；填写目标总数量后点击应用。';return $data
}
$play.Add_Click({Start-Process "$root/Play-Local.cmd" -WorkingDirectory $root -WindowStyle Hidden});$console.Add_Click({Start-Process 'http://127.0.0.1:8088/console'})
$refresh.Add_Click({try{$null=Read-Current}catch{Failure $_.Exception.Message}})
$heal.Add_Click({try{$null=Invoke-LocalGameCommand 'heal';$status.Text='已恢复当前队伍生命并复活倒下角色。'}catch{Failure $_.Exception.Message}})
$apply.Add_Click({$apply.Enabled=$false;try{$before=Invoke-LocalGameCommand 'status';$before|ConvertTo-Json -Depth 5 -Compress|Add-Content "$root/logs/manager-currency-history.jsonl" -Encoding UTF8;foreach($field in $fields){$amount=[int]$boxes[$field.key].Value;if($amount -ne [int]$before.($field.key)){$null=Invoke-LocalGameCommand "set $($field.id) $amount"}};$null=Read-Current;$status.Text='已设置为填写的总数量。'}catch{Failure $_.Exception.Message}finally{$apply.Enabled=$true}})
$banners.Add_Click({try{if($character.Text -notmatch '^\s*(\d+)'){throw '请选择角色'};$avatarId=$Matches[1];if($weapon.Text -notmatch '^\s*(\d+)'){throw '请选择武器'};$weaponId=$Matches[1];$null=Invoke-LocalGameCommand "banner $avatarId $weaponId";$status.Text='已保存 UP，重新打开游戏祈愿查看。'}catch{Failure $_.Exception.Message}})
. "$root/runtime/Manager-GearUI.ps1"
if($Check -or $CheckOnline){
    if($boxes.Count -ne 11 -or $tabs.TabPages.Count -ne 7 -or $character.Items.Count -ne 69 -or $weapon.Items.Count -ne 90){throw 'UI construction failed'}
    if([Math]::Abs($labels.mora.Top-$boxes.mora.Top) -gt 5){throw 'Mora label misaligned'}
    if(!$qty.AutoScroll){throw 'Materials cannot scroll'}
    if($CheckOnline){
        if((Get-Command Invoke-LocalGameCommand).CommandType -ne 'Function'){throw 'Command resolution conflict'}
        $snapshot=Read-Current
        foreach($field in $fields){if(!$boxes[$field.key].Enabled -or $boxes[$field.key].Value -ne [decimal]$snapshot.($field.key)){throw "Readback failed: $($field.key)"}}
        Read-Warehouse
        if($list.Items.Count -ne $script:warehouseRows.Count){throw 'Warehouse readback failed'}
        Read-Gear
        if($ownedAvatar.Items.Count -ne $script:gearRows.avatars.Count){throw 'Owned avatar readback failed'}
        $request=Get-ArtifactRequest
        $validation=Invoke-LocalGearAction 'validate' $request
        if(!$validation.ok){throw 'Artifact validation failed'}
        $currentWorld=Read-WorldLevel
        if(!$worldApply.Enabled -or $worldLevel.Value -ne $currentWorld){throw 'World level readback failed'}
        "PASS: actual manager command path reads all 11 quantities and $($list.Items.Count) warehouse weapons; owned gear readback and artifact server validation passed. No account data changed."
    }
    'PASS: UI construction, aligned Mora label and scroll layout.'
    $form.Dispose();exit
}
$form.Add_Shown({try{$null=Read-Current}catch{$status.Text='请先进入游戏，再点“读取当前数量”。'}})
[Windows.Forms.Application]::Run($form)
