$gearCatalog=Get-Content "$root/runtime/gear-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
function Invoke-LocalGearAction([string]$Action,$Payload=$null){
    $command="localgear $Action"
    if($null -ne $Payload){$json=$Payload|ConvertTo-Json -Depth 8 -Compress;$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json));$command+=" $encoded"}
    $reply=& "$root/console-command.ps1" -Command "$command @10001";$message=$reply.output -join "`n"
    if($message -notmatch '^\s*\{'){throw $message};$message|ConvertFrom-Json
}
function Gear-Combo($parent,$x,$y,$width){$control=New-Object Windows.Forms.ComboBox;$control.DropDownStyle='DropDownList';$control.Location=New-Object Drawing.Point($x,$y);$control.Width=$width;$control.MaxDropDownItems=20;$parent.Controls.Add($control);Disable-Wheel $control;return $control}
function Invoke-GearUpgradeBatch($Requests,$Action='upgrade') {
    $results=@();$position=0
    foreach($request in $Requests){
        $position++;$status.Text="正在处理 $position / $($Requests.Count)：$($request.name)";$status.Refresh()
        $row=[ordered]@{name=$request.name;type=$request.type;id=$request.id;guid=$request.guid;state='';message=''}
        if($Action -eq 'talents'){try{$result=Invoke-LocalGearAction 'talents' @{id=[int]$request.id};if(!$result.ok){throw '服务端未确认成功'};$row.state='success';$row.message="已升满 $($result.count) 项天赋（基础最高 10 级）"}catch{$row.state='failed';$row.message=$_.Exception.Message}}
        elseif($request.level -ge $request.maxLevel -and $request.promote -ge $request.maxPromote){$row.state='skipped';$row.message='已满级满突破，保持原状'}
        elseif($request.level -gt $request.maxLevel){$row.state='skipped';$row.message='特殊超上限等级，保持原状'}
        else{try{$payload=if($request.type -eq 'avatar'){@{type='avatar';id=[int]$request.id}}else{@{type='weapon';guid=[string]$request.guid}};$result=Invoke-LocalGearAction 'upgrade' $payload;if(!$result.ok){throw '服务端未确认成功'};$row.state='success';$row.message="Lv.$($result.level)，突破 $($result.promote) 阶"}catch{$row.state='failed';$row.message=$_.Exception.Message}}
        $results+=[pscustomobject]$row
    }
    return $results
}

# ---------------- 角色／武器培养 ----------------
$gearLayout=New-Table 2 4;Add-Col $gearLayout 'Percent' 50;Add-Col $gearLayout 'Percent' 50;Add-Row $gearLayout 'AutoSize';Add-Row $gearLayout 'Percent' 100;Add-Row $gearLayout 'AutoSize';Add-Row $gearLayout 'Absolute' 120;$gearTab.Controls.Add($gearLayout)
$gearHint=New-Label '① 勾选角色和武器（可搜索）　② 点下方按钮执行。不扣材料；已满级满突破的会跳过；不改命座、精炼和装备归属。' -Muted 900
$gearLayout.Controls.Add($gearHint,0,0);$gearLayout.SetColumnSpan($gearHint,2)
function New-GearPicker([string]$Title){
    $box=New-Object Windows.Forms.GroupBox;$box.Text=$Title;$box.Dock='Fill';$box.Padding=New-Object Windows.Forms.Padding(8,4,8,4)
    $t=New-Table 1 3;$t.Padding=New-Object Windows.Forms.Padding(0);Add-Col $t 'Percent' 100;Add-Row $t 'AutoSize';Add-Row $t 'Percent' 100;Add-Row $t 'AutoSize';$box.Controls.Add($t)
    $top=New-Flow;$top.WrapContents=$false;$search=New-Object Windows.Forms.TextBox;$search.Width=170;$search.Margin=New-Object Windows.Forms.Padding(3,6,8,3)
    Add-Flow $top (New-Label '搜索') $search;$t.Controls.Add($top,0,0)
    $checklist=New-Object Windows.Forms.CheckedListBox;$checklist.Dock='Fill';$checklist.CheckOnClick=$true;$checklist.HorizontalScrollbar=$true;$checklist.IntegralHeight=$false;$t.Controls.Add($checklist,0,1)
    $bottom=New-Flow;$all=New-Button '全选' 80;$none=New-Button '清空' 80;$count=New-Label '未读取' -Muted;Add-Flow $bottom $all $none $count;$t.Controls.Add($bottom,0,2)
    return @{box=$box;top=$top;search=$search;list=$checklist;all=$all;none=$none;count=$count}
}
$avatarPicker=New-GearPicker '角色';$weaponPicker=New-GearPicker '武器'
$gearLayout.Controls.Add($avatarPicker.box,0,1);$gearLayout.Controls.Add($weaponPicker.box,1,1)
$ownedAvatar=$avatarPicker.list;$ownedWeapon=$weaponPicker.list
$weaponFilter=New-Object Windows.Forms.ComboBox;$weaponFilter.DropDownStyle='DropDownList';$weaponFilter.Width=130;$weaponFilter.Margin=New-Object Windows.Forms.Padding(3,6,3,3);$weaponFilter.Items.AddRange([object[]]@('已装备','全部','五星','四星','三星及以下','仓库中（未装备）'));$weaponFilter.SelectedIndex=0;$weaponPicker.top.Controls.Add($weaponFilter);Disable-Wheel $weaponFilter
$gearActions=New-Flow
$gearBatch=New-Button '升满级＋突破（勾选的角色和武器）' 290 -Primary;$gearBatch.Enabled=$false
$talentBatch=New-Button '天赋满级（勾选的角色）' 210;$talentBatch.Enabled=$false
$talentNote=New-Label '天赋基础最高 10 级，命座加成保留；旅行者只处理当前元素。' -Muted
Add-Flow $gearActions $gearBatch $talentBatch $talentNote;$gearLayout.Controls.Add($gearActions,0,2);$gearLayout.SetColumnSpan($gearActions,2)
$gearResults=New-Object Windows.Forms.TextBox;$gearResults.Multiline=$true;$gearResults.ReadOnly=$true;$gearResults.ScrollBars='Vertical';$gearResults.Dock='Fill';$gearResults.Text='执行结果会显示在这里。'
$gearLayout.Controls.Add($gearResults,0,3);$gearLayout.SetColumnSpan($gearResults,2)
$script:gearRows=$null;$script:allAvatarRows=@();$script:allWeaponRows=@();$script:avatarUpgradeRows=@();$script:weaponUpgradeRows=@()

function Get-GearState($item){if($item.level -ge $item.maxLevel -and $item.promote -ge $item.maxPromote){'✓ 已满'}else{''}}
function Get-CheckedKeys($control,$rows,[string]$Key){$keys=@{};foreach($i in $control.CheckedIndices){$keys[[string]$rows[$i].$Key]=$true};return $keys}
function Show-AvatarRows{
    $keep=Get-CheckedKeys $ownedAvatar $script:avatarUpgradeRows 'id';$q=$avatarPicker.search.Text.Trim()
    $script:avatarUpgradeRows=@($script:allAvatarRows|Where-Object {!$q -or $_.display -like "*$q*"})
    $ownedAvatar.BeginUpdate();$ownedAvatar.Items.Clear();foreach($item in $script:avatarUpgradeRows){$i=$ownedAvatar.Items.Add($item.display);if($keep.ContainsKey([string]$item.id)){$ownedAvatar.SetItemChecked($i,$true)}};$ownedAvatar.EndUpdate();Update-GearCounts
}
function Test-WeaponFilter($item){
    switch($weaponFilter.SelectedIndex){0{[bool]$item.equipped};1{$true};2{$item.rank -eq 5};3{$item.rank -eq 4};4{$item.rank -le 3};5{!$item.equipped};default{$true}}
}
function Read-UpgradeableWeapons{
    $keep=Get-CheckedKeys $ownedWeapon $script:weaponUpgradeRows 'guid';$q=$weaponPicker.search.Text.Trim()
    $script:weaponUpgradeRows=@($script:allWeaponRows|Where-Object {(Test-WeaponFilter $_) -and (!$q -or $_.display -like "*$q*")})
    $ownedWeapon.BeginUpdate();$ownedWeapon.Items.Clear();foreach($item in $script:weaponUpgradeRows){$i=$ownedWeapon.Items.Add($item.display);if($keep.ContainsKey([string]$item.guid)){$ownedWeapon.SetItemChecked($i,$true)}};$ownedWeapon.EndUpdate();Update-GearCounts
}
function Update-GearCounts{
    $a=$ownedAvatar.CheckedIndices.Count;$w=$ownedWeapon.CheckedIndices.Count
    $avatarPicker.count.Text="已选 $a / 显示 $($ownedAvatar.Items.Count)";$weaponPicker.count.Text="已选 $w / 显示 $($ownedWeapon.Items.Count)"
    $gearBatch.Enabled=($a+$w) -gt 0;$talentBatch.Enabled=$a -gt 0
    $gearBatch.Text=if($a+$w){"升满级＋突破（$a 角色，$w 武器）"}else{'升满级＋突破（勾选的角色和武器）'};$talentBatch.Text=if($a){"天赋满级（$a 名角色）"}else{'天赋满级（勾选的角色）'}
}
function Set-GearData($data){
    $script:gearRows=$data
    $script:allAvatarRows=@($data.avatars|Sort-Object id|ForEach-Object {$name=$script:avatarNames[[string]$_.id];if(!$name){$name=if($_.id -in @(10000005,10000007)){'旅行者'}else{"角色 $($_.id)"}};$_|Add-Member -NotePropertyName display -NotePropertyValue "$name  Lv.$($_.level)/$($_.maxLevel)  突破$($_.promote)  $(Get-GearState $_)" -Force -PassThru})
    $script:allWeaponRows=@($data.weapons|Sort-Object @{Expression='rank';Descending=$true},id,level,guid|ForEach-Object {$name=$weaponNames.([string]$_.id);if(!$name){$name="武器 $($_.id)"};$where=if($_.equipped){'已装备'}else{'仓库'};$guid=[string]$_.guid;$short=if($guid.Length -gt 6){$guid.Substring($guid.Length-6)}else{$guid};$_|Add-Member -NotePropertyName display -NotePropertyValue "$name  $($_.rank)★  Lv.$($_.level)/$($_.maxLevel)  突破$($_.promote)  $where  $(Get-GearState $_)  #$short" -Force -PassThru})
    # Fresh data from the server clears old ticks so a stale selection is never executed.
    $script:avatarUpgradeRows=@();$script:weaponUpgradeRows=@();$ownedAvatar.Items.Clear();$ownedWeapon.Items.Clear()
    Show-AvatarRows;Read-UpgradeableWeapons
}
function Read-Gear {Set-GearData (Invoke-LocalGearAction 'list');$status.Text="已读取 $($script:allAvatarRows.Count) 名角色、$($script:allWeaponRows.Count) 把武器，请勾选。"}
function Get-CheckedGearRequests {
    $requests=@()
    foreach($index in $ownedAvatar.CheckedIndices){$item=$script:avatarUpgradeRows[$index];$requests+=@{type='avatar';id=$item.id;name=[string]$ownedAvatar.Items[$index];level=$item.level;promote=$item.promote;maxLevel=$item.maxLevel;maxPromote=$item.maxPromote}}
    foreach($index in $ownedWeapon.CheckedIndices){$item=$script:weaponUpgradeRows[$index];$requests+=@{type='weapon';guid=[string]$item.guid;name=[string]$ownedWeapon.Items[$index];level=$item.level;promote=$item.promote;maxLevel=$item.maxLevel;maxPromote=$item.maxPromote}}
    return $requests
}
function Invoke-CheckedGearBatch([string]$Action='upgrade') {
    $requests=@(Get-CheckedGearRequests);if($Action -eq 'talents'){$requests=@($requests|Where-Object type -eq 'avatar')}
    if(!$requests.Count){Failure '请先勾选要处理的角色或武器；天赋操作只处理角色。';return}
    $avatarCount=@($requests|Where-Object type -eq 'avatar').Count;$weaponCount=$requests.Count-$avatarCount
    $question=if($Action -eq 'talents'){"将把 $avatarCount 名角色的天赋升到满级（不扣材料）。确定执行？"}else{"将把 $avatarCount 名角色、$weaponCount 把武器升到满级并完成突破（不扣材料，已满的跳过）。确定执行？"}
    if(!(Confirm-Action $question '确认批量培养')){return}
    Invoke-UiAction '正在批量处理…' {
        $results=@(Invoke-GearUpgradeBatch $requests $Action)
        $gearResults.Lines=[string[]]@($results|ForEach-Object {$tag=switch($_.state){success{'成功'};skipped{'跳过'};failed{'失败'}};"[$tag] $($_.name)：$($_.message)"})
        @{time=[DateTime]::Now.ToString('o');action=$Action;results=$results}|ConvertTo-Json -Depth 8 -Compress|Add-Content "$root/logs/manager-gear-batches.jsonl" -Encoding UTF8
        $success=@($results|Where-Object state -eq 'success').Count;$failed=@($results|Where-Object state -eq 'failed').Count;$skipped=@($results|Where-Object state -eq 'skipped').Count
        try{$data=Invoke-LocalGearAction 'list';Set-GearData $data;Set-WarehouseData $data}catch{$gearResults.AppendText("`r`n刷新清单失败：$($_.Exception.Message)")}
        Set-Status "批量完成：成功 $success，跳过 $skipped，失败 $failed。明细见页面底部。"
    }
}
$avatarPicker.search.Add_TextChanged({Show-AvatarRows});$weaponPicker.search.Add_TextChanged({Read-UpgradeableWeapons});$weaponFilter.Add_SelectedIndexChanged({Read-UpgradeableWeapons})
$ownedAvatar.Add_ItemCheck({$null=$form.BeginInvoke([Action]{Update-GearCounts})});$ownedWeapon.Add_ItemCheck({$null=$form.BeginInvoke([Action]{Update-GearCounts})})
$avatarPicker.all.Add_Click({for($i=0;$i -lt $ownedAvatar.Items.Count;$i++){$ownedAvatar.SetItemChecked($i,$true)}})
$avatarPicker.none.Add_Click({for($i=0;$i -lt $ownedAvatar.Items.Count;$i++){$ownedAvatar.SetItemChecked($i,$false)}})
$weaponPicker.all.Add_Click({for($i=0;$i -lt $ownedWeapon.Items.Count;$i++){$ownedWeapon.SetItemChecked($i,$true)}})
$weaponPicker.none.Add_Click({for($i=0;$i -lt $ownedWeapon.Items.Count;$i++){$ownedWeapon.SetItemChecked($i,$false)}})
$gearBatch.Add_Click({Invoke-CheckedGearBatch 'upgrade'})
$talentBatch.Add_Click({Invoke-CheckedGearBatch 'talents'})

# ---------------- 自定义圣遗物 ----------------
$null=Label $artifactTab '生成一件新的五星圣遗物到背包：自动锁定，不覆盖、不自动装备已有圣遗物。' 20 12 860
$null=Label $artifactTab '套装' 20 52 90;$setChoice=Gear-Combo $artifactTab 120 48 440
$script:artifactSets=@($gearCatalog.sets|Sort-Object @{Expression={$_.name -like '*待补充*'}},name)
foreach($set in $script:artifactSets){$null=$setChoice.Items.Add("$($set.name)（$($set.id)）")}
$null=Label $artifactTab '部位' 20 94 90;$slotChoice=Gear-Combo $artifactTab 120 90 200
$slotTypes=@('EQUIP_BRACER','EQUIP_NECKLACE','EQUIP_SHOES','EQUIP_RING','EQUIP_DRESS');$slotChoice.Items.AddRange(@('生之花','死之羽','时之沙','空之杯','理之冠'))
$null=Label $artifactTab '强化等级' 340 94 80;$artifactLevel=New-Object Windows.Forms.NumericUpDown;$artifactLevel.Location=New-Object Drawing.Point(425,90);$artifactLevel.Width=70;$artifactLevel.Maximum=20;$artifactLevel.Value=20;$artifactTab.Controls.Add($artifactLevel);Disable-Wheel $artifactLevel
$null=Label $artifactTab '主词条' 20 136 90;$mainChoice=Gear-Combo $artifactTab 120 132 440
$null=Label $artifactTab '副词条' 20 180 90;$null=Label $artifactTab '次数（含初始 1 次）' 340 180 160;$null=Label $artifactTab '最终数值' 515 180 120
$subChoices=@();$subCounts=@();$subValues=@()
for($i=0;$i -lt 4;$i++){
    $subChoices+=Gear-Combo $artifactTab 120 (210+$i*40) 210
    $n=New-Object Windows.Forms.NumericUpDown;$n.Location=New-Object Drawing.Point(345,(210+$i*40));$n.Width=65;$n.Minimum=1;$n.Maximum=6;$n.Value=if($i -eq 0){6}else{1};$artifactTab.Controls.Add($n);$subCounts+=$n;Disable-Wheel $n
    $subValues+=Label $artifactTab '' 515 (213+$i*40) 160
}
$artifactPreview=Label $artifactTab '' 20 375 860 52
$createArtifact=Button $artifactTab '生成这件五星圣遗物' 120 432 300;Set-Primary $createArtifact
$null=Label $artifactTab '数值按该词条最高单档累加；允许主副词条相同，四条副词条之间不能重复。' 20 480 860 |ForEach-Object {$_.ForeColor=$MutedColor}
$script:artifactUpdating=$false;$script:artifactPiece=$null;$script:mainRows=@();$script:subRows=@()
function Update-ArtifactPreview {
    if($script:artifactUpdating -or $null -eq $script:artifactPiece){return};$total=0;$props=@()
    for($i=0;$i -lt 4;$i++){$count=[int]$subCounts[$i].Value;$total+=$count;$index=$subChoices[$i].SelectedIndex;if($index -ge 0){$sub=$script:subRows[$index];$props+=$sub.prop;$value=[double]$sub.value*$count;$subValues[$i].Text=if($sub.percent){($value*100).ToString('0.0')+'%'}else{$value.ToString('0')}}}
    $duplicates=@($props|Group-Object|Where-Object Count -gt 1|ForEach-Object Name)
    for($i=0;$i -lt 4;$i++){$index=$subChoices[$i].SelectedIndex;$subChoices[$i].BackColor=if($index -ge 0 -and $script:subRows[$index].prop -in $duplicates){$BadColor}else{[Drawing.SystemColors]::Window}}
    $required=4+[Math]::Floor([double]$artifactLevel.Value/4);$left=$required-$total
    $problem=if($duplicates.Count){'副词条重复了（红色标出），请换一条。'}elseif($left -gt 0){"还需要再分配 $left 次。"}elseif($left -lt 0){"多分配了 $(-$left) 次，请减少。"}else{''}
    $artifactPreview.Text="强化次数合计 $total / $required。"+$(if($problem){$problem}else{'可以生成。'})
    $artifactPreview.ForeColor=if($problem){[Drawing.Color]::Firebrick}else{[Drawing.Color]::DarkGreen};$createArtifact.Enabled=!$problem
}
function Update-ArtifactSubs {
    if($script:artifactUpdating -or $mainChoice.SelectedIndex -lt 0){return};$script:artifactUpdating=$true
    try{$script:subRows=@($script:artifactPiece.subs);$preferences=@('FIGHT_PROP_CRITICAL','FIGHT_PROP_CRITICAL_HURT','FIGHT_PROP_ATTACK_PERCENT','FIGHT_PROP_CHARGE_EFFICIENCY','FIGHT_PROP_HP_PERCENT','FIGHT_PROP_DEFENSE_PERCENT');$chosen=@();for($i=0;$i -lt 4;$i++){$subChoices[$i].Items.Clear();foreach($sub in $script:subRows){$null=$subChoices[$i].Items.Add($sub.name)};$preference=@($preferences|Where-Object {$_ -notin $chosen -and $_ -in $script:subRows.prop})[0];$selected=0;for($j=0;$j -lt $script:subRows.Count;$j++){if($script:subRows[$j].prop -eq $preference){$selected=$j;break}};$subChoices[$i].SelectedIndex=$selected;$chosen+=$script:subRows[$selected].prop}}
    finally{$script:artifactUpdating=$false};Update-ArtifactPreview
}
function Update-ArtifactPiece {
    if($script:artifactUpdating -or $setChoice.SelectedIndex -lt 0 -or $slotChoice.SelectedIndex -lt 0){return}
    $setId=$script:artifactSets[$setChoice.SelectedIndex].id;$slot=$slotTypes[$slotChoice.SelectedIndex];$script:artifactPiece=$gearCatalog.items|Where-Object {$_.setId -eq $setId -and $_.slot -eq $slot}|Select-Object -First 1
    $mainChoice.Items.Clear();if(!$script:artifactPiece){$createArtifact.Enabled=$false;$artifactPreview.ForeColor=[Drawing.Color]::Firebrick;$artifactPreview.Text='此套装没有这个部位，请选择其他部位。';return};$script:artifactUpdating=$true
    try{$script:mainRows=@($script:artifactPiece.mains);foreach($main in $script:mainRows){$null=$mainChoice.Items.Add($main.name)};if($mainChoice.Items.Count){$mainChoice.SelectedIndex=0}}finally{$script:artifactUpdating=$false};Update-ArtifactSubs
}
function Get-ArtifactRequest {
    if(!$script:artifactPiece -or $mainChoice.SelectedIndex -lt 0){throw '请先选择有效套装、部位和主词条'};$subs=@();$seen=@();$total=0
    for($i=0;$i -lt 4;$i++){if($subChoices[$i].SelectedIndex -lt 0){throw '请选择四条副词条'};$sub=$script:subRows[$subChoices[$i].SelectedIndex];if($sub.prop -in $seen){throw '副词条不能重复'};$seen+=$sub.prop;$count=[int]$subCounts[$i].Value;$total+=$count;$subs+=@{id=[int]$sub.id;count=$count}}
    $expected=4+[Math]::Floor([double]$artifactLevel.Value/4);if($total -ne $expected){throw "四项次数合计应为 $expected，目前是 $total"}
    @{item=[int]$script:artifactPiece.id;level=[int]$artifactLevel.Value;main=[int]$script:mainRows[$mainChoice.SelectedIndex].id;subs=$subs}
}
$setChoice.Add_SelectedIndexChanged({Update-ArtifactPiece});$slotChoice.Add_SelectedIndexChanged({Update-ArtifactPiece});$mainChoice.Add_SelectedIndexChanged({Update-ArtifactSubs})
foreach($control in $subChoices){$control.Add_SelectedIndexChanged({Update-ArtifactPreview})};foreach($control in $subCounts){$control.Add_ValueChanged({Update-ArtifactPreview})}
$artifactLevel.Add_ValueChanged({$extra=[int][Math]::Floor([double]$artifactLevel.Value/4);$script:artifactUpdating=$true;try{for($i=0;$i -lt 4;$i++){$subCounts[$i].Maximum=1+$extra;$subCounts[$i].Value=if($i -eq 0){1+$extra}else{1}}}finally{$script:artifactUpdating=$false};Update-ArtifactPreview})
$createArtifact.Add_Click({Invoke-UiAction '正在生成圣遗物…' {$request=Get-ArtifactRequest;$result=Invoke-LocalGearAction 'artifact' $request;Set-Status "已生成并锁定一件 +$($result.level) $($slotChoice.Text)（$($setChoice.Text)），请到背包查看。"}})
if($setChoice.Items.Count){$setChoice.SelectedIndex=0};$slotChoice.SelectedIndex=0

# ---------------- 世界等级／皮肤 ----------------
$worldBox=New-Object Windows.Forms.GroupBox;$worldBox.Text='世界等级（0～9）';$worldBox.Location=New-Object Drawing.Point(16,12);$worldBox.Size=New-Object Drawing.Size(880,200);$worldTab.Controls.Add($worldBox)
$worldCurrent=Label $worldBox '当前世界等级：待读取' 18 32 400
$null=Label $worldBox '目标等级' 18 76 90
$worldLevel=New-Object Windows.Forms.NumericUpDown;$worldLevel.Location=New-Object Drawing.Point(110,72);$worldLevel.Width=90;$worldLevel.Minimum=0;$worldLevel.Maximum=9;$worldLevel.Enabled=$false;$worldBox.Controls.Add($worldLevel);Disable-Wheel $worldLevel
$worldApply=Button $worldBox '应用世界等级' 220 68 180;$worldApply.Enabled=$false
$null=Label $worldBox "等级越高，怪物越强、奖励档位越高。不修改冒险等级，只能修改自己的世界。`n已刷出的怪物不一定立即变级，切换区域或重新进入世界后生效。" 18 122 850 60|ForEach-Object {$_.ForeColor=$MutedColor}
$skinBox=New-Object Windows.Forms.GroupBox;$skinBox.Text='角色皮肤／风之翼';$skinBox.Location=New-Object Drawing.Point(16,228);$skinBox.Size=New-Object Drawing.Size(880,210);$worldTab.Controls.Add($skinBox)
$null=Label $skinBox "进入世界后会自动解锁全部角色衣装和风之翼，不替换你当前穿的。`n游戏内更换：角色界面（C）→选择角色→右下角衣架／装扮。需要先拥有对应角色。" 18 30 850 56
$skinInfo=Label $skinBox '如果游戏里仍显示未解锁，点下面按钮重新检查并补齐。' 18 92 850 50;$skinInfo.ForeColor=$MutedColor
$skinRead=Button $skinBox '检查并补齐全部皮肤与风之翼' 18 148 300
function Set-WorldData($data){
    if($null -eq $data.worldLevel){$worldCurrent.Text='当前世界等级：服务端尚未支持';return}
    $worldLevel.Value=[int]$data.worldLevel;$worldCurrent.Text="当前世界等级：$($data.worldLevel)";$worldLevel.Enabled=$true;$worldApply.Enabled=$true
}
function Read-WorldLevel {
    $data=Invoke-LocalGearAction 'list'
    if($null -eq $data.worldLevel){throw '服务端尚未更新世界等级功能'}
    Set-WorldData $data;return [int]$data.worldLevel
}
$worldApply.Add_Click({
    $target=[int]$worldLevel.Value;if(!(Confirm-Action "将世界等级设为 $target。确定？" '确认世界等级')){return}
    Invoke-UiAction '正在设置世界等级…' {$result=Invoke-LocalGearAction 'world' @{level=$target};$actual=Read-WorldLevel;if(!$result.ok -or $actual -ne $target){throw '世界等级回读不一致，请重新读取'};Set-Status "世界等级已设为 $actual 并保存。"}
})
$skinRead.Add_Click({Invoke-UiAction '正在检查皮肤与风之翼…' {$null=Invoke-LocalGearAction 'wingsync';$r=Invoke-LocalGearAction 'skins';if(!$r.ok){throw '解锁未完成'};$skinInfo.Text="已解锁 $($r.unlocked) / $($r.total) 件角色衣装（含默认衣装），本次新增 $($r.added) 件；风之翼 $($r.wingsUnlocked) / $($r.wingsTotal)。";Set-Status '皮肤与风之翼已补齐，请在游戏角色装扮界面更换。'}})
