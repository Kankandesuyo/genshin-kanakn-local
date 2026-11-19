$gearCatalog=Get-Content "$root/runtime/gear-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
function Invoke-LocalGearAction([string]$Action,$Payload=$null){
    $command="localgear $Action"
    if($null -ne $Payload){$json=$Payload|ConvertTo-Json -Depth 8 -Compress;$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json));$command+=" $encoded"}
    $reply=& "$root/console-command.ps1" -Command "$command @10001";$message=$reply.output -join "`n"
    if($message -notmatch '^\s*\{'){throw $message};$message|ConvertFrom-Json
}
function Gear-Combo($parent,$x,$y,$width){$control=New-Object Windows.Forms.ComboBox;$control.DropDownStyle='DropDownList';$control.Location=New-Object Drawing.Point($x,$y);$control.Width=$width;$parent.Controls.Add($control);return $control}
$gearTab=New-Object Windows.Forms.TabPage('角色／武器升级');$artifactTab=New-Object Windows.Forms.TabPage('自定义圣遗物');$artifactTab.AutoScroll=$true;$tabs.TabPages.AddRange(@($gearTab,$artifactTab))
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
function New-GearChecklist($parent,$y){$control=New-Object Windows.Forms.CheckedListBox;$control.Location=New-Object Drawing.Point(20,$y);$control.Size=New-Object Drawing.Size(565,130);$control.CheckOnClick=$true;$control.HorizontalScrollbar=$true;$parent.Controls.Add($control);return $control}
$gearTab.AutoScroll=$true
$gearRefresh=Button $gearTab '读取已拥有的角色和武器' 20 12 565
$null=Label $gearTab '角色：勾选需要升级、突破的多个角色' 20 56 565
$ownedAvatar=New-GearChecklist $gearTab 88
$avatarAll=Button $gearTab '角色全选' 20 225 160;$avatarNone=Button $gearTab '清空角色勾选' 195 225 160
$equippedOnly=New-Object Windows.Forms.CheckBox;$equippedOnly.Text='武器：只看已装备（取消可选择仓库武器）';$equippedOnly.Checked=$true;$equippedOnly.Location=New-Object Drawing.Point(20,275);$equippedOnly.Width=565;$gearTab.Controls.Add($equippedOnly)
$ownedWeapon=New-GearChecklist $gearTab 310
$weaponAll=Button $gearTab '武器全选' 20 447 160;$weaponNone=Button $gearTab '清空武器勾选' 195 447 160
$gearBatch=Button $gearTab '批量升满＋突破：执行所有勾选的角色和武器' 20 498 565;$gearBatch.Enabled=$false
$null=Label $gearTab "不扣材料；已满级的会跳过，失败的单独显示。`n不修改命座、天赋、精炼和装备归属。`n读取或切换武器筛选后会清空对应勾选，请重新选择。" 20 546 570 85
$gearResults=New-Object Windows.Forms.TextBox;$gearResults.Multiline=$true;$gearResults.ReadOnly=$true;$gearResults.ScrollBars='Vertical';$gearResults.Location=New-Object Drawing.Point(20,638);$gearResults.Size=New-Object Drawing.Size(565,150);$gearTab.Controls.Add($gearResults)
foreach($control in @($gearTab.Controls)){if($control.Top -ge 275){$control.Top+=55}}
$gearBatch.Location=New-Object Drawing.Point(370,225);$gearBatch.Size=New-Object Drawing.Size(215,36);$gearBatch.Text='勾选角色／武器升满突破'
$talentBatch=Button $gearTab '勾选角色：一键天赋满级（不扣材料）' 20 270 565;$talentBatch.Enabled=$false
$null=Label $gearTab '天赋基础最高 10 级；命座加成保留。旅行者只处理当前元素。' 20 850 570 55
$script:gearRows=$null;$script:weaponUpgradeRows=@()
function Read-UpgradeableWeapons {
    $ownedWeapon.Items.Clear();$script:weaponUpgradeRows=@($script:gearRows.weapons|Where-Object {!$equippedOnly.Checked -or $_.equipped}|Sort-Object id,level,guid)
    foreach($item in $script:weaponUpgradeRows){$name=$weaponNames.([string]$item.id);if(!$name){$name="武器 $($item.id)"};$suffix=if($item.equipped){'已装备'}else{'仓库'};$null=$ownedWeapon.Items.Add("$name  Lv.$($item.level)/$($item.maxLevel)  突破$($item.promote)  $suffix  #$($item.guid)")}
}
function Read-Gear {
    $script:gearRows=Invoke-LocalGearAction 'list';$script:avatarUpgradeRows=@($script:gearRows.avatars|Sort-Object id);$ownedAvatar.Items.Clear()
    foreach($item in $script:avatarUpgradeRows){$name=($catalog.avatars|Where-Object avatarId -eq $item.id|Select-Object -First 1).name;if(!$name){$name=if($item.id -in @(10000005,10000007)){'旅行者'}else{"角色 $($item.id)"}};$null=$ownedAvatar.Items.Add("$name  Lv.$($item.level)/$($item.maxLevel)  突破$($item.promote)")}
    Read-UpgradeableWeapons;$gearBatch.Enabled=$true;$talentBatch.Enabled=$true
    $status.Text="已读取 $($script:avatarUpgradeRows.Count) 名角色、$($script:gearRows.weapons.Count) 把武器，请勾选。"
}
function Get-CheckedGearRequests {
    $requests=@()
    foreach($index in $ownedAvatar.CheckedIndices){$item=$script:avatarUpgradeRows[$index];$requests+=@{type='avatar';id=$item.id;name=[string]$ownedAvatar.Items[$index];level=$item.level;promote=$item.promote;maxLevel=$item.maxLevel;maxPromote=$item.maxPromote}}
    foreach($index in $ownedWeapon.CheckedIndices){$item=$script:weaponUpgradeRows[$index];$requests+=@{type='weapon';guid=[string]$item.guid;name=[string]$ownedWeapon.Items[$index];level=$item.level;promote=$item.promote;maxLevel=$item.maxLevel;maxPromote=$item.maxPromote}}
    return $requests
}
$gearRefresh.Add_Click({try{Read-Gear}catch{Failure $_.Exception.Message}})
$equippedOnly.Add_CheckedChanged({if($null -ne $script:gearRows){Read-UpgradeableWeapons}})
$avatarAll.Add_Click({for($i=0;$i -lt $ownedAvatar.Items.Count;$i++){$ownedAvatar.SetItemChecked($i,$true)}})
$avatarNone.Add_Click({for($i=0;$i -lt $ownedAvatar.Items.Count;$i++){$ownedAvatar.SetItemChecked($i,$false)}})
$weaponAll.Add_Click({for($i=0;$i -lt $ownedWeapon.Items.Count;$i++){$ownedWeapon.SetItemChecked($i,$true)}})
$weaponNone.Add_Click({for($i=0;$i -lt $ownedWeapon.Items.Count;$i++){$ownedWeapon.SetItemChecked($i,$false)}})
function Invoke-CheckedGearBatch([string]$Action='upgrade') {
    try{
        $requests=@(Get-CheckedGearRequests);if($Action -eq 'talents'){$requests=@($requests|Where-Object type -eq 'avatar')};if(!$requests.Count){throw '请先勾选要处理的角色或武器；天赋操作只处理角色'}
        $gearTab.Enabled=$false
        $results=@(Invoke-GearUpgradeBatch $requests $Action)
        $gearResults.Lines=[string[]]@($results|ForEach-Object {$tag=switch($_.state){success{'成功'};skipped{'跳过'};failed{'失败'}};"[$tag] $($_.name)：$($_.message)"})
        @{time=[DateTime]::Now.ToString('o');action=$Action;results=$results}|ConvertTo-Json -Depth 8 -Compress|Add-Content "$root/logs/manager-gear-batches.jsonl" -Encoding UTF8
        $success=@($results|Where-Object state -eq 'success').Count;$failed=@($results|Where-Object state -eq 'failed').Count;$skipped=@($results|Where-Object state -eq 'skipped').Count
        try{Read-Gear}catch{$gearResults.AppendText("`r`n刷新清单失败：$($_.Exception.Message)")}
        $status.Text="批量完成：成功 $success，跳过 $skipped，失败 $failed。下滚查看明细。";$gearTab.ScrollControlIntoView($gearResults)
    }catch{Failure $_.Exception.Message}finally{$gearTab.Enabled=$true}
}
$gearBatch.Add_Click({Invoke-CheckedGearBatch 'upgrade'})
$talentBatch.Add_Click({Invoke-CheckedGearBatch 'talents'})
$null=Label $artifactTab '生成一件新的五星圣遗物；默认锁定，不覆盖已有装备。' 15 10
$null=Label $artifactTab '套装' 18 48 90;$setChoice=Gear-Combo $artifactTab 120 43 440
$script:artifactSets=@($gearCatalog.sets|Sort-Object @{Expression={$_.name -like '*待补充*'}},name)
foreach($set in $script:artifactSets){$null=$setChoice.Items.Add("$($set.name)（$($set.id)）")}
$null=Label $artifactTab '部位' 18 92 90;$slotChoice=Gear-Combo $artifactTab 120 87 250
$slotTypes=@('EQUIP_BRACER','EQUIP_NECKLACE','EQUIP_SHOES','EQUIP_RING','EQUIP_DRESS');$slotChoice.Items.AddRange(@('生之花','死之羽','时之沙','空之杯','理之冠'))
$null=Label $artifactTab '强化等级' 18 138 100;$artifactLevel=New-Object Windows.Forms.NumericUpDown;$artifactLevel.Location=New-Object Drawing.Point(120,132);$artifactLevel.Width=90;$artifactLevel.Maximum=20;$artifactLevel.Value=20;$artifactTab.Controls.Add($artifactLevel)
$null=Label $artifactTab '主词条' 18 183 90;$mainChoice=Gear-Combo $artifactTab 120 177 440
$null=Label $artifactTab '副词条（次数包含初始 1 次；显示值按最高单档计算）' 18 216 570
$subChoices=@();$subCounts=@();$subValues=@()
for($i=0;$i -lt 4;$i++){
    $subChoices+=Gear-Combo $artifactTab 20 (248+$i*42) 300
    $n=New-Object Windows.Forms.NumericUpDown;$n.Location=New-Object Drawing.Point(340,(248+$i*42));$n.Width=65;$n.Minimum=1;$n.Maximum=6;$n.Value=if($i -eq 0){6}else{1};$artifactTab.Controls.Add($n);$subCounts+=$n
    $subValues+=Label $artifactTab '' 425 (250+$i*42) 160
}
$artifactPreview=Label $artifactTab '' 20 425 570 65
$createArtifact=Button $artifactTab '生成这件五星圣遗物到背包' 20 498 540
$script:artifactUpdating=$false;$script:artifactPiece=$null;$script:mainRows=@();$script:subRows=@()
function Update-ArtifactPreview {
    if($script:artifactUpdating -or $null -eq $script:artifactPiece){return};$total=0
    for($i=0;$i -lt 4;$i++){$count=[int]$subCounts[$i].Value;$total+=$count;$index=$subChoices[$i].SelectedIndex;if($index -ge 0){$sub=$script:subRows[$index];$value=[double]$sub.value*$count;$subValues[$i].Text=if($sub.percent){($value*100).ToString('0.0')+'%'}else{$value.ToString('0')}}}
    $required=4+[Math]::Floor([double]$artifactLevel.Value/4);$artifactPreview.Text="次数合计 $total / $required。允许主副词条相同；四条副词条仍须互不重复。`n只调整等级、主副词条和强化次数；成品会自动锁定。";$artifactPreview.ForeColor=if($total -eq $required){[Drawing.Color]::DarkGreen}else{[Drawing.Color]::Firebrick}
}
function Update-ArtifactSubs {
    if($script:artifactUpdating -or $mainChoice.SelectedIndex -lt 0){return};$script:artifactUpdating=$true
    try{$main=$script:mainRows[$mainChoice.SelectedIndex];$script:subRows=@($script:artifactPiece.subs);$preferences=@('FIGHT_PROP_CRITICAL','FIGHT_PROP_CRITICAL_HURT','FIGHT_PROP_ATTACK_PERCENT','FIGHT_PROP_CHARGE_EFFICIENCY','FIGHT_PROP_HP_PERCENT','FIGHT_PROP_DEFENSE_PERCENT');$chosen=@();for($i=0;$i -lt 4;$i++){$subChoices[$i].Items.Clear();foreach($sub in $script:subRows){$null=$subChoices[$i].Items.Add($sub.name)};$preference=@($preferences|Where-Object {$_ -notin $chosen -and $_ -in $script:subRows.prop})[0];$selected=0;for($j=0;$j -lt $script:subRows.Count;$j++){if($script:subRows[$j].prop -eq $preference){$selected=$j;break}};$subChoices[$i].SelectedIndex=$selected;$chosen+=$script:subRows[$selected].prop}}
    finally{$script:artifactUpdating=$false};Update-ArtifactPreview
}
function Update-ArtifactPiece {
    if($script:artifactUpdating -or $setChoice.SelectedIndex -lt 0 -or $slotChoice.SelectedIndex -lt 0){return}
    $setId=$script:artifactSets[$setChoice.SelectedIndex].id;$slot=$slotTypes[$slotChoice.SelectedIndex];$script:artifactPiece=$gearCatalog.items|Where-Object {$_.setId -eq $setId -and $_.slot -eq $slot}|Select-Object -First 1
    $mainChoice.Items.Clear();if(!$script:artifactPiece){$createArtifact.Enabled=$false;$artifactPreview.Text='此套装没有这个部位，请选择其他部位。';return};$createArtifact.Enabled=$true;$script:artifactUpdating=$true
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
$artifactLevel.Add_ValueChanged({$extra=[int][Math]::Floor([double]$artifactLevel.Value/4);for($i=0;$i -lt 4;$i++){$subCounts[$i].Value=if($i -eq 0){1+$extra}else{1}};Update-ArtifactPreview})
$createArtifact.Add_Click({try{$request=Get-ArtifactRequest;$result=Invoke-LocalGearAction 'artifact' $request;$status.Text="已生成并锁定一件 +$($result.level) 五星圣遗物，请到背包查看。"}catch{Failure $_.Exception.Message}})
if($setChoice.Items.Count){$setChoice.SelectedIndex=0};$slotChoice.SelectedIndex=0

$worldTab=New-Object Windows.Forms.TabPage('世界等级');$tabs.TabPages.Add($worldTab)
$null=Label $worldTab '自定义自己的世界等级（0～9）' 20 20 550
$worldCurrent=Label $worldTab '当前世界等级：待读取' 20 62 550
$worldLevel=New-Object Windows.Forms.NumericUpDown;$worldLevel.Location=New-Object Drawing.Point(200,112);$worldLevel.Width=150;$worldLevel.Minimum=0;$worldLevel.Maximum=9;$worldLevel.Enabled=$false;$worldTab.Controls.Add($worldLevel)
$null=Label $worldTab '想设置的等级' 20 116 170
$worldRead=Button $worldTab '读取当前世界等级' 20 170 250
$worldApply=Button $worldTab '应用世界等级' 295 170 250;$worldApply.Enabled=$false
$null=Label $worldTab "等级越高，通常怪物更强、奖励档位更高。`n不修改冒险等级；只能修改自己的世界。`n已刷出的怪物不一定立即变级，切换区域或重新进入世界后查看。" 20 235 560 100
function Read-WorldLevel {
    $data=Invoke-LocalGearAction 'list'
    if($null -eq $data.worldLevel){throw '服务端尚未更新世界等级功能'}
    $worldLevel.Value=[int]$data.worldLevel;$worldCurrent.Text="当前世界等级：$($data.worldLevel)";$worldLevel.Enabled=$true;$worldApply.Enabled=$true
    return [int]$data.worldLevel
}
$worldRead.Add_Click({try{$null=Read-WorldLevel;$status.Text='已读取世界等级，可以填写并应用。'}catch{Failure $_.Exception.Message}})
$worldApply.Add_Click({$worldApply.Enabled=$false;try{$target=[int]$worldLevel.Value;$result=Invoke-LocalGearAction 'world' @{level=$target};$actual=Read-WorldLevel;if(!$result.ok -or $actual -ne $target){throw '世界等级回读不一致，请重新读取'};$status.Text="世界等级已设为 $actual 并保存。"}catch{Failure $_.Exception.Message}finally{$worldApply.Enabled=$worldLevel.Enabled}})

$skinTab=New-Object Windows.Forms.TabPage('皮肤／风之翼');$tabs.TabPages.Add($skinTab)
$null=Label $skinTab '默认解锁全部角色衣装和风之翼' 20 20 560
$null=Label $skinTab "游戏入口：打开角色界面（C）→选择角色→右下角衣架／装扮。`n再选择衣装并更换；需要先拥有对应角色。`n只解锁，不自动替换你当前穿的皮肤。" 20 65 565 110
$skinInfo=Label $skinTab '进入世界后会自动补齐；无需逐件购买或领取。' 20 185 560 65
$skinRead=Button $skinTab '检查并补齐全部皮肤与风之翼' 20 270 550
$skinRead.Add_Click({try{$null=Invoke-LocalGearAction 'wingsync';$r=Invoke-LocalGearAction 'skins';if(!$r.ok){throw '解锁未完成'};$skinInfo.Text="已解锁 $($r.unlocked) / $($r.total) 件角色衣装（含默认衣装）。本次新增 $($r.added) 件。风之翼 $($r.wingsUnlocked) / $($r.wingsTotal)。";$status.Text='角色皮肤已补齐，请在游戏角色装扮界面更换。'}catch{Failure $_.Exception.Message}})
