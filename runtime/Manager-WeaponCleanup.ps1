$cleanupLayout=New-Table 1 5;Add-Col $cleanupLayout 'Percent' 100;Add-Row $cleanupLayout 'AutoSize';Add-Row $cleanupLayout 'AutoSize';Add-Row $cleanupLayout 'Percent' 100;Add-Row $cleanupLayout 'AutoSize';Add-Row $cleanupLayout 'AutoSize';$warehouse.Controls.Add($cleanupLayout)
$cleanupLayout.Controls.Add((New-Label "勾选要清理的四星武器，或一键清理全部可清理的三星武器。每把三星返还 3 个、四星返还 10 个精锻用魔矿；不返还强化和精炼投入。`n锁定或已装备的武器始终受保护，五星武器不会出现在这里。执行前会再次弹窗确认。" -Muted 900),0,0)
$cleanupFilter=New-Flow
$hideProtected=New-Object Windows.Forms.CheckBox;$hideProtected.Text='隐藏锁定／已装备';$hideProtected.Checked=$true;$hideProtected.AutoSize=$true;$hideProtected.Margin=New-Object Windows.Forms.Padding(3,10,12,3)
$fourAll=New-Button '全选可清理' 130;$fourNone=New-Button '清空勾选' 110
Add-Flow $cleanupFilter $hideProtected $fourAll $fourNone;$cleanupLayout.Controls.Add($cleanupFilter,0,1)
$list=New-Object Windows.Forms.CheckedListBox;$list.CheckOnClick=$true;$list.HorizontalScrollbar=$true;$list.Dock='Fill';$list.IntegralHeight=$false;$cleanupLayout.Controls.Add($list,0,2)
$fourActions=New-Flow
$recycle=New-Button '清理勾选的四星' 170 -Primary;$recycle.Enabled=$false;$fourInfo=New-Label '先读取数据。' -Muted
Add-Flow $fourActions $recycle $fourInfo;$cleanupLayout.Controls.Add($fourActions,0,3)
$threeBox=New-Object Windows.Forms.GroupBox;$threeBox.Text='三星武器';$threeBox.Dock='Fill';$threeBox.Height=80
$threeFlow=New-Flow;$threeFlow.Padding=New-Object Windows.Forms.Padding(6,2,6,2)
$threeCleanup=New-Button '一键清理三星武器' 190;$threeCleanup.Enabled=$false;$cleanupInfo=New-Label '先读取数据。' -Muted
Add-Flow $threeFlow $threeCleanup $cleanupInfo;$threeBox.Controls.Add($threeFlow);$cleanupLayout.Controls.Add($threeBox,0,4)
$script:warehouseRows=@();$script:threeRows=@();$script:allFourRows=@()
function Update-CleanupCounts{
    $checked=$list.CheckedIndices.Count
    $fourInfo.Text=if($checked){"已勾选 $checked 把，预计返还 $($checked*10) 个精锻用魔矿（矿石满仓时，确认框会提示放弃多少）。"}else{"共 $(@($script:allFourRows).Count) 把四星，其中可清理 $(@($script:allFourRows|Where-Object {!$_.protected}).Count) 把。"}
    $recycle.Enabled=$checked -gt 0
}
function Show-FourStarRows([switch]$KeepChecks){
    $keep=@{};if($KeepChecks){foreach($i in $list.CheckedIndices){$keep[[string]$script:warehouseRows[$i].guid]=$true}}
    $script:warehouseRows=@($script:allFourRows|Where-Object {!$hideProtected.Checked -or !$_.protected})
    $list.BeginUpdate();$list.Items.Clear()
    foreach($item in $script:warehouseRows){$name=$weaponNames.([string]$item.id);if(!$name){$name="四星武器 $($item.id)"};$tag=if($item.protected){'【锁定／已装备，受保护】'}else{''};$index=$list.Items.Add("$name  Lv.$($item.level)  $tag  #$($item.guid)");if($keep.ContainsKey([string]$item.guid)){$list.SetItemChecked($index,$true)}}
    $list.EndUpdate();Update-CleanupCounts
}
function Set-WarehouseData($data){
    $script:allFourRows=@($data.weapons|Where-Object rank -eq 4|Sort-Object protected,id,level,guid);$script:threeRows=@($data.weapons|Where-Object rank -eq 3)
    Show-FourStarRows
    $threeFree=@($script:threeRows|Where-Object {!$_.protected}).Count;$threeCleanup.Enabled=$threeFree -gt 0
    $threeCleanup.Text=if($threeFree){"一键清理 $threeFree 把三星"}else{'没有可清理的三星'}
    $cleanupInfo.Text="三星共 $($script:threeRows.Count) 把，可清理 $threeFree 把，预计返还 $($threeFree*3) 个精锻用魔矿。"
}
function Read-Warehouse {Set-WarehouseData (Invoke-LocalGearAction 'list');$status.Text='已读取武器仓库。'}
function Get-WeaponCleanupRequest([int]$Rank){
    $guids=@()
    if($Rank -eq 3){$guids=@($script:threeRows|Where-Object {!$_.protected}|ForEach-Object {[string]$_.guid})}
    elseif($Rank -eq 4){foreach($index in $list.CheckedIndices){$item=$script:warehouseRows[$index];if(!$item.protected){$guids+=[string]$item.guid}}}
    else{throw '仅支持三星和四星'}
    return @{rank=$Rank;guids=@($guids)}
}
function Invoke-WeaponCleanup([int]$Rank){
    Invoke-UiAction '正在预检要清理的武器…' {
        if($Rank -eq 3){Read-Warehouse}
        $request=Get-WeaponCleanupRequest $Rank;if(!$request.guids.Count){throw '没有可清理的武器，请先勾选。'}
        $preview=Invoke-LocalGearAction 'recyclecheck' $request
        if(!$preview.ok -or $preview.eligible -lt 1){throw '选中的武器已不存在或受保护，请点「刷新全部数据」后重新选择。'}
        $overflowNote=if($preview.overflow -gt 0){"`n`n矿石容量不足：其中 $($preview.overflow) 个返还矿石会被放弃，现有矿石不会减少。"}else{''}
        $answer=[Windows.Forms.MessageBox]::Show("将删除 $($preview.eligible) 把 $Rank 星武器，返还 $($preview.reward) 个精锻用魔矿。$overflowNote`n`n锁定、已装备的武器会跳过；强化和精炼投入不返还。`n删除后无法撤销，确定清理？",'确认清理武器','YesNo','Warning')
        if($answer -ne 'Yes'){Set-Status '已取消清理。';return}
        $request.allowOverflow=$preview.overflow -gt 0;$request.maxOverflow=[int]$preview.overflow
        Set-Status '正在清理…';$result=Invoke-LocalGearAction 'recyclebatch' $request
        @{time=[DateTime]::Now.ToString('o');request=$request;result=$result}|ConvertTo-Json -Depth 8 -Compress|Add-Content "$root/logs/manager-weapon-cleanup.jsonl" -Encoding UTF8
        $data=Invoke-LocalGearAction 'list';Set-WarehouseData $data;Set-GearData $data;$null=Read-Current
        Set-Status "已清理 $($result.removed) 把，返还 $($result.reward) 个矿石，跳过 $($result.skipped) 把，放弃溢出 $($result.overflow) 个。"
        if($result.failures.Count){Failure ($result.failures -join "`n")}
    }
}
$list.Add_ItemCheck({param($sender,$event)if($script:warehouseRows[$event.Index].protected){$event.NewValue=[Windows.Forms.CheckState]::Unchecked};$null=$form.BeginInvoke([Action]{Update-CleanupCounts})})
$hideProtected.Add_CheckedChanged({Show-FourStarRows -KeepChecks})
$fourAll.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){if(!$script:warehouseRows[$i].protected){$list.SetItemChecked($i,$true)}}})
$fourNone.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){$list.SetItemChecked($i,$false)}})
$recycle.Add_Click({Invoke-WeaponCleanup 4});$threeCleanup.Add_Click({Invoke-WeaponCleanup 3})
