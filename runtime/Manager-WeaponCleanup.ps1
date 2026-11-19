$form.Text='原神 7.1 本地服管理器【清理修复版 10.17】'
$warehouse.Text='武器清理'
$null=Label $warehouse "四星：勾选多把一起清理；三星：一键清理未锁定、未装备的武器。`n每把三星返还 3 个、四星返还 10 个精锻用魔矿；不返还强化投入。" 14 10 580 60
$list=New-Object Windows.Forms.CheckedListBox;$list.CheckOnClick=$true;$list.HorizontalScrollbar=$true;$list.Location=New-Object Drawing.Point(15,78);$list.Size=New-Object Drawing.Size(580,170);$warehouse.Controls.Add($list)
$warehouseRefresh=Button $warehouse '读取仓库' 15 255 130
$fourAll=Button $warehouse '全选可清理四星' 150 255 170
$fourNone=Button $warehouse '清空勾选' 325 255 125
$recycle=Button $warehouse '清理勾选四星' 455 255 145;$recycle.Enabled=$false
$threeCleanup=Button $warehouse '一键清理三星武器' 15 307 580;$threeCleanup.Enabled=$false
$cleanupInfo=Label $warehouse '先读取仓库；锁定和已装备的武器会受保护。' 15 355 580 45
$script:warehouseRows=@();$script:threeRows=@()
function Read-Warehouse {
    $data=Invoke-LocalGearAction 'list';$list.Items.Clear();$script:warehouseRows=@($data.weapons|Where-Object rank -eq 4|Sort-Object id,level,guid);$script:threeRows=@($data.weapons|Where-Object rank -eq 3)
    foreach($item in $script:warehouseRows){$name=$weaponNames.([string]$item.id);if(!$name){$name="四星武器 $($item.id)"};$tag=if($item.protected){'【锁定／已装备】'}else{'可清理'};$null=$list.Items.Add("$name  Lv.$($item.level)  $tag  #$($item.guid)")}
    $recycle.Enabled=$script:warehouseRows.Count -gt 0;$threeCleanup.Enabled=@($script:threeRows|Where-Object {!$_.protected}).Count -gt 0
    $cleanupInfo.Text="四星 $($script:warehouseRows.Count) 把；三星 $($script:threeRows.Count) 把，其中可清理 $(@($script:threeRows|Where-Object {!$_.protected}).Count) 把。"
    $status.Text='已读取武器仓库，请勾选四星或一键清理三星。'
}
function Get-WeaponCleanupRequest([int]$Rank){
    $guids=@()
    if($Rank -eq 3){$guids=@($script:threeRows|Where-Object {!$_.protected}|ForEach-Object {[string]$_.guid})}
    elseif($Rank -eq 4){foreach($index in $list.CheckedIndices){$item=$script:warehouseRows[$index];if(!$item.protected){$guids+=[string]$item.guid}}}
    else{throw '仅支持三星和四星'}
    return @{rank=$Rank;guids=@($guids)}
}
function Invoke-WeaponCleanup([int]$Rank){
    try{
        if($Rank -eq 3){Read-Warehouse}
        $request=Get-WeaponCleanupRequest $Rank;if(!$request.guids.Count){throw '没有可清理的武器，请先读取并勾选'}
        $preview=Invoke-LocalGearAction 'recyclecheck' $request
        if(!$preview.ok -or $preview.eligible -lt 1){throw '选中的武器已不存在或受保护，请重新读取'}
        $overflowNote=if($preview.overflow -gt 0){"`n矿石容量不足：另有 $($preview.overflow) 个返还矿石将放弃；现有矿石不会减少。"}else{''}
        $answer=[Windows.Forms.MessageBox]::Show("将删除 $($preview.eligible) 把 $Rank 星武器，返还 $($preview.reward) 个精锻用魔矿。$overflowNote`n锁定、已装备武器会跳过。强化和精炼投入不返还。`n删除后无法在管理器撤销，确定清理？",'确认批量清理','YesNo','Warning')
        if($answer -ne 'Yes'){return}
        $request.allowOverflow=$preview.overflow -gt 0;$request.maxOverflow=[int]$preview.overflow
        $warehouse.Enabled=$false;$result=Invoke-LocalGearAction 'recyclebatch' $request
        @{time=[DateTime]::Now.ToString('o');request=$request;result=$result}|ConvertTo-Json -Depth 8 -Compress|Add-Content "$root/logs/manager-weapon-cleanup.jsonl" -Encoding UTF8
        Read-Warehouse;$null=Read-Current
        $status.Text="已清理 $($result.removed) 把，返还 $($result.reward) 矿石，跳过 $($result.skipped) 把，放弃溢出 $($result.overflow) 矿石。"
        if($result.failures.Count){Failure ($result.failures -join "`n")}
    }catch{Failure $_.Exception.Message}finally{$warehouse.Enabled=$true}
}
$warehouseRefresh.Add_Click({try{Read-Warehouse}catch{Failure $_.Exception.Message}})
$list.Add_ItemCheck({param($sender,$event)if($script:warehouseRows[$event.Index].protected){$event.NewValue=[Windows.Forms.CheckState]::Unchecked}})
$fourAll.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){if(!$script:warehouseRows[$i].protected){$list.SetItemChecked($i,$true)}}})
$fourNone.Add_Click({for($i=0;$i -lt $list.Items.Count;$i++){$list.SetItemChecked($i,$false)}})
$recycle.Add_Click({Invoke-WeaponCleanup 4});$threeCleanup.Add_Click({Invoke-WeaponCleanup 3})
