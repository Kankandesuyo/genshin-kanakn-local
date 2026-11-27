param([switch]$Check,[switch]$CheckOnline)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=Split-Path $PSScriptRoot -Parent
$catalog=Get-Content "$root/runtime/manager-catalog.json" -Raw -Encoding UTF8|ConvertFrom-Json
$weaponNames=Get-Content "$root/runtime/weapon-names-zh.json" -Raw -Encoding UTF8|ConvertFrom-Json
$script:avatarNames=@{};foreach($a in $catalog.avatars){$script:avatarNames[[string]$a.avatarId]=$a.name}
function Invoke-LocalGameCommand([string]$Arguments){$r=& "$root/console-command.ps1" -Command "localgm $Arguments @10001";$text=$r.output -join "`n";if($text -notmatch '^\s*\{'){throw $text};$text|ConvertFrom-Json}

# ---------------- UI helpers ----------------
$AccentColor=[Drawing.Color]::FromArgb(47,98,204)
$MutedColor=[Drawing.Color]::FromArgb(105,112,128)
$ChangedColor=[Drawing.Color]::FromArgb(255,241,196)
$BadColor=[Drawing.Color]::FromArgb(255,222,222)
function Label($parent,$text,$x,$y,$width=570,$height=30){$c=New-Object Windows.Forms.Label;$c.Text=$text;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,$height);if($parent){$parent.Controls.Add($c)};return $c}
function Button($parent,$text,$x,$y,$width=180){$c=New-Object Windows.Forms.Button;$c.Text=$text;$c.Location=New-Object Drawing.Point($x,$y);$c.Size=New-Object Drawing.Size($width,36);if($parent){$parent.Controls.Add($c)};return $c}
function New-Label([string]$Text,[switch]$Muted,[int]$Wrap=0){$c=New-Object Windows.Forms.Label;$c.Text=$Text;$c.AutoSize=$true;$c.Anchor='Left';$c.Margin=New-Object Windows.Forms.Padding(3,7,3,7);if($Muted){$c.ForeColor=$MutedColor};if($Wrap){$c.MaximumSize=New-Object Drawing.Size($Wrap,0)};return $c}
function New-Button([string]$Text,[int]$Width=150,[switch]$Primary){$c=New-Object Windows.Forms.Button;$c.Text=$Text;$c.Size=New-Object Drawing.Size($Width,34);$c.Margin=New-Object Windows.Forms.Padding(3,4,6,4);if($Primary){Set-Primary $c};return $c}
function Set-Primary($c){$c.ForeColor=[Drawing.Color]::White;$c.FlatStyle='Flat';$c.FlatAppearance.BorderSize=0;$c.BackColor=$AccentColor;$c.Add_EnabledChanged({$this.BackColor=if($this.Enabled){$AccentColor}else{[Drawing.Color]::FromArgb(176,186,206)}})}
function New-Table([int]$Columns,[int]$Rows){$t=New-Object Windows.Forms.TableLayoutPanel;$t.Dock='Fill';$t.ColumnCount=$Columns;$t.RowCount=$Rows;$t.Padding=New-Object Windows.Forms.Padding(8);return $t}
function Add-Col($t,[string]$Type,$Value=0){$null=$t.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]$Type,[single]$Value)))}
function Add-Row($t,[string]$Type,$Value=0){$null=$t.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]$Type,[single]$Value)))}
function New-Flow{$f=New-Object Windows.Forms.FlowLayoutPanel;$f.AutoSize=$true;$f.AutoSizeMode='GrowAndShrink';$f.Dock='Fill';$f.Margin=New-Object Windows.Forms.Padding(0);return $f}
function Add-Flow($flow){foreach($c in $args){$flow.Controls.Add($c)}}
function Disable-Wheel($control){$control.Add_MouseWheel({$_.Handled=$true})}
function Format-Number($value){'{0:N0}' -f [decimal]$value}

# ---------------- main window ----------------
$form=New-Object Windows.Forms.Form;$form.Text='原神 7.2 本地服管理器';$form.ClientSize=New-Object Drawing.Size(980,720);$form.MinimumSize=New-Object Drawing.Size(880,660);$form.StartPosition='CenterScreen';$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10);$form.BackColor=[Drawing.Color]::FromArgb(245,247,251)
$header=New-Object Windows.Forms.TableLayoutPanel;$header.Dock='Top';$header.AutoSize=$true;$header.ColumnCount=1;$header.RowCount=2;$header.Padding=New-Object Windows.Forms.Padding(10,6,10,2)
$titleRow=New-Flow;$titleRow.WrapContents=$false
$title=New-Object Windows.Forms.Label;$title.Text='原神本地服管理器';$title.AutoSize=$true;$title.Font=New-Object Drawing.Font('Microsoft YaHei UI',16,[Drawing.FontStyle]::Bold)
$connection=New-Label '● 未连接' -Muted;$connection.Margin=New-Object Windows.Forms.Padding(14,12,3,3)
Add-Flow $titleRow $title $connection
$toolbar=New-Flow;$toolbar.WrapContents=$false
$play=New-Button '启动游戏' 120 -Primary;$refresh=New-Button '刷新全部数据' 140;$heal=New-Button '队伍回血／复活' 150;$console=New-Button '网页控制台' 120
$lastRead=New-Label '' -Muted
Add-Flow $toolbar $play $refresh $heal $console $lastRead
$header.Controls.Add($titleRow,0,0);$header.Controls.Add($toolbar,0,1)
$status=New-Object Windows.Forms.Label;$status.Dock='Bottom';$status.Height=32;$status.TextAlign='MiddleLeft';$status.AutoEllipsis=$true;$status.Padding=New-Object Windows.Forms.Padding(12,0,12,0);$status.BackColor=[Drawing.Color]::White;$status.Text='准备就绪。'
$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$tabs.Padding=New-Object Drawing.Point(14,5)
$form.Controls.Add($header);$form.Controls.Add($status);$form.Controls.Add($tabs);$tabs.BringToFront()
$qty=New-Object Windows.Forms.TabPage('资源数量');$qty.AutoScroll=$true
$gearTab=New-Object Windows.Forms.TabPage('角色／武器培养')
$artifactTab=New-Object Windows.Forms.TabPage('自定义圣遗物');$artifactTab.AutoScroll=$true
$banner=New-Object Windows.Forms.TabPage('卡池 UP')
$warehouse=New-Object Windows.Forms.TabPage('武器清理')
$worldTab=New-Object Windows.Forms.TabPage('世界等级／皮肤');$worldTab.AutoScroll=$true
$tabs.TabPages.AddRange(@($qty,$gearTab,$artifactTab,$banner,$warehouse,$worldTab))
foreach($page in $tabs.TabPages){$page.BackColor=$form.BackColor}

# ---------------- shared behaviour ----------------
$script:busy=$false;$script:online=$false
function Set-Status([string]$Text){$status.Text=$Text;$status.Refresh()}
function Get-FriendlyError([string]$Message){
    if($Message -match 'Unable to connect|无法连接|actively refused|积极拒绝|No connection could be made|由于目标计算机'){return '本地服务端没有运行。请点「启动游戏」，等进入游戏世界后再操作。'}
    if($Message -match 'offline|not online|不在线|未在线|Player not found|找不到玩家'){return '玩家不在线。请先进入游戏世界，再点「刷新全部数据」。'}
    return $Message
}
function Failure($problem){$status.Text='操作未完成，请查看提示。';[Windows.Forms.MessageBox]::Show([string]$problem,'操作未完成','OK','Warning')|Out-Null}
function Set-Connection([bool]$Online,[string]$Detail=''){
    $script:online=$Online
    if($Online){$connection.Text='● 已连接，玩家在线';$connection.ForeColor=[Drawing.Color]::SeaGreen}
    else{$connection.Text="● 未连接$(if($Detail){'：'+$Detail})";$connection.ForeColor=[Drawing.Color]::IndianRed}
}
function Invoke-UiAction([string]$BusyText,[scriptblock]$Work){
    if($script:busy){return};$script:busy=$true;$form.UseWaitCursor=$true;$tabs.Enabled=$false;$toolbar.Enabled=$false
    if($BusyText){Set-Status $BusyText};[Windows.Forms.Application]::DoEvents()
    try{& $Work}
    catch{$friendly=Get-FriendlyError $_.Exception.Message;if($friendly -ne $_.Exception.Message){Set-Connection $false '请进入游戏'};Failure $friendly}
    finally{$tabs.Enabled=$true;$toolbar.Enabled=$true;$form.UseWaitCursor=$false;$script:busy=$false}
}
function Confirm-Action([string]$Text,[string]$Caption='请确认'){[Windows.Forms.MessageBox]::Show($Text,$Caption,'YesNo','Question') -eq 'Yes'}

# ---------------- 资源数量 ----------------
$fields=@(
    @{key='primogems';id=201;label='原石';max=100000000;group=0},@{key='mora';id=202;label='摩拉';max=100000000;group=0},
    @{key='intertwined';id=223;label='纠缠之缘';max=100000000;group=0},@{key='acquaint';id=224;label='相遇之缘';max=100000000;group=0},
    @{key='resin';id=106;label='原粹树脂';max=2000;group=0},@{key='item104003';id=104003;label='大英雄的经验（紫书）';max=99999;group=1},
    @{key='item104002';id=104002;label='冒险家的经验（蓝书）';max=99999;group=1},@{key='item104001';id=104001;label='流浪者的经验（绿书）';max=99999;group=1},
    @{key='item104013';id=104013;label='精锻用魔矿';max=99999;group=1},@{key='item104012';id=104012;label='精锻用良矿';max=99999;group=1},@{key='item104011';id=104011;label='精锻用杂矿';max=99999;group=1})
$qtyLayout=New-Table 2 3;Add-Col $qtyLayout 'Percent' 50;Add-Col $qtyLayout 'Percent' 50;Add-Row $qtyLayout 'AutoSize';Add-Row $qtyLayout 'Absolute' 275;Add-Row $qtyLayout 'AutoSize';$qty.Controls.Add($qtyLayout)
$qtyHint=New-Label '填写想拥有的总数量（不是增加量）。改过的项会高亮，点「应用修改」前会列出全部变化让你确认；填 0 即清零。' -Muted 900
$qtyLayout.Controls.Add($qtyHint,0,0);$qtyLayout.SetColumnSpan($qtyHint,2)
$qtyGrids=@()
foreach($groupInfo in @(@{title='货币与树脂';col=0},@{title='养成材料';col=1})){
    $box=New-Object Windows.Forms.GroupBox;$box.Text=$groupInfo.title;$box.Dock='Fill';$box.Padding=New-Object Windows.Forms.Padding(10,6,10,6)
    $grid=New-Table 3 6;$grid.Padding=New-Object Windows.Forms.Padding(2);Add-Col $grid 'AutoSize';Add-Col $grid 'Absolute' 150;Add-Col $grid 'AutoSize';for($r=0;$r -lt 6;$r++){Add-Row $grid 'AutoSize'}
    $box.Controls.Add($grid);$qtyLayout.Controls.Add($box,$groupInfo.col,1);$qtyGrids+=$grid
}
$boxes=@{};$labels=@{};$originals=@{};$rowIndex=@(0,0)
foreach($field in $fields){
    $grid=$qtyGrids[$field.group];$row=$rowIndex[$field.group];$rowIndex[$field.group]++
    $l=New-Label $field.label;$n=New-Object Windows.Forms.NumericUpDown;$n.Width=140;$n.Anchor='Left';$n.Minimum=0;$n.Maximum=$field.max;$n.ThousandsSeparator=$true;$n.Enabled=$false;$n.Tag=$field.key;$n.Margin=New-Object Windows.Forms.Padding(3,5,3,5)
    $o=New-Label '' -Muted
    $grid.Controls.Add($l,0,$row);$grid.Controls.Add($n,1,$row);$grid.Controls.Add($o,2,$row)
    $labels[$field.key]=$l;$boxes[$field.key]=$n;$originals[$field.key]=$o;Disable-Wheel $n
}
$qtyActions=New-Flow
$apply=New-Button '应用修改' 180 -Primary;$apply.Enabled=$false;$revert=New-Button '撤销修改' 120;$revert.Enabled=$false
$qtyNote=New-Label '修改前的数量会记录到 logs/manager-currency-history.jsonl。' -Muted
Add-Flow $qtyActions $apply $revert $qtyNote
$qtyLayout.Controls.Add($qtyActions,0,2);$qtyLayout.SetColumnSpan($qtyActions,2)
$script:loadedQty=@{};$script:loadingQty=$false
function Get-QtyChanges{@($fields|Where-Object {$script:loadedQty.ContainsKey($_.key) -and [decimal]$boxes[$_.key].Value -ne [decimal]$script:loadedQty[$_.key]})}
function Update-QtyDirty{
    if($script:loadingQty){return};$changes=@(Get-QtyChanges)
    foreach($field in $fields){$dirty=$field -in $changes;$boxes[$field.key].BackColor=if($dirty){$ChangedColor}else{[Drawing.SystemColors]::Window};$labels[$field.key].Font=New-Object Drawing.Font($form.Font,$(if($dirty){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}))}
    $apply.Text=if($changes.Count){"应用修改（$($changes.Count) 项）"}else{'应用修改'};$apply.Enabled=$changes.Count -gt 0;$revert.Enabled=$changes.Count -gt 0
}
foreach($n in $boxes.Values){$n.Add_ValueChanged({Update-QtyDirty})}

# ---------------- 卡池 UP ----------------
function New-SearchCombo($parent,$x,$y,$items){$c=New-Object Windows.Forms.ComboBox;$c.Location=New-Object Drawing.Point($x,$y);$c.Width=380;$c.DropDownStyle='DropDown';$c.AutoCompleteMode='SuggestAppend';$c.AutoCompleteSource='ListItems';$c.MaxDropDownItems=20;$c.Items.AddRange([object[]]$items);$parent.Controls.Add($c);Disable-Wheel $c;return $c}
$null=Label $banner '选择或输入名字搜索（例如「雷电」），保存后关闭再打开祈愿界面即可生效。' 20 16 820 28
$bannerCurrent=Label $banner '当前 UP：待读取' 20 50 820 28;$bannerCurrent.ForeColor=$MutedColor
$null=Label $banner '角色池五星 UP' 20 96 150
$character=New-SearchCombo $banner 180 92 @($catalog.avatars|Where-Object {$_.stars -eq 5}|ForEach-Object {"$($_.id) $($_.name)"})
$null=Label $banner '武器池五星 UP' 20 146 150
$weapon=New-SearchCombo $banner 180 142 @($catalog.weapons|ForEach-Object {"$($_.id) $($_.name)"})
$banners=Button $banner '保存卡池 UP' 180 196 200;Set-Primary $banners
$bannerReset=Button $banner '恢复为当前 UP' 395 196 165
$null=Label $banner "四类卡池（常驻、角色 UP、武器 UP、混合）分别统计抽数与保底。`n保存只修改实际 UP 内容；卡面图片沿用兼容模板，可能与所选不一致，以祈愿「详情」为准。`n此操作不会增加货币，抽卡道具请在「资源数量」页设置。" 20 252 820 90 |ForEach-Object {$_.ForeColor=$MutedColor}
$script:currentUp=@{character=$null;weapon=$null}
function Resolve-ComboId($combo,[string]$what){
    $text=$combo.Text.Trim();if($text -match '^\s*(\d+)'){return $Matches[1]}
    if($text){$match=@($combo.Items|Where-Object {$_ -like "* $text*"});if($match.Count -eq 1 -and $match[0] -match '^(\d+)'){$combo.Text=$match[0];return $Matches[1]};if($match.Count -gt 1){throw "「$text」匹配到多个$what，请从下拉列表中选择一个。"}}
    throw "请选择$what。"
}
function Set-ComboById($combo,$id){if($null -eq $id){return};$m=@($combo.Items|Where-Object {$_ -like "$id *"});$combo.Text=if($m.Count){$m[0]}else{[string]$id}}

$wishNames=@{}
foreach($item in @($catalog.avatars)+@($catalog.weapons)){$wishNames[[string]$item.id]=$item.name}
function Format-WishNames($ids){
    (@(foreach($id in $ids){$name=$wishNames[[string]$id];if($name){$name}else{[string]$id}}) -join '、')
}
function Show-BannerUp($characters,$weapons,$caption){
    $script:currentUp.character=@($characters)[0]
    $script:currentUp.weapon=@($weapons)[0]
    Set-ComboById $character $script:currentUp.character
    Set-ComboById $weapon $script:currentUp.weapon
    $bannerCurrent.Text="${caption}：角色 $(Format-WishNames $characters)　｜　武器 $(Format-WishNames $weapons)"
}
$poolFile=Join-Path $root 'server/data/LocalBanners.json'
if(Test-Path $poolFile){
    $poolRows=Get-Content $poolFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $actorPool=$poolRows | Where-Object bannerType -eq 'CHARACTER' | Select-Object -First 1
    $weaponPool=$poolRows | Where-Object bannerType -eq 'WEAPON' | Select-Object -First 1
    if($actorPool -and $weaponPool){
        Show-BannerUp $actorPool.rateUpItems5 $weaponPool.rateUpItems5 '已配置 UP'
        $null=Label $banner ("角色池四星 UP："+(Format-WishNames $actorPool.rateUpItems4)) 20 345 820 32
    }
}

function Read-Current {
    $data=Invoke-LocalGameCommand 'status'
    $script:loadingQty=$true
    try{
        foreach($field in $fields){$value=$data.($field.key);if($null -eq $value){throw '服务端尚未更新，请重新进入游戏。'};$boxes[$field.key].Maximum=[Math]::Max([decimal]$field.max,[decimal]$value);$boxes[$field.key].Value=[decimal]$value;$boxes[$field.key].Enabled=$true;$script:loadedQty[$field.key]=[decimal]$value;$originals[$field.key].Text="当前 $(Format-Number $value)"}
    }finally{$script:loadingQty=$false};Update-QtyDirty
    Show-BannerUp $data.characterUp $data.weaponUp "当前 UP"
    Set-Connection $true;$status.Text='已读取；填写目标总数量后点击应用。';return $data
}

. "$root/runtime/Manager-WeaponCleanup.ps1"
. "$root/runtime/Manager-GearUI.ps1"

function Read-All {
    $null=Read-Current
    $data=Invoke-LocalGearAction 'list'
    Set-GearData $data;Set-WarehouseData $data;Set-WorldData $data
    Set-Connection $true;$lastRead.Text="上次读取 $(Get-Date -Format 'HH:mm:ss')"
}

# ---------------- events ----------------
$play.Add_Click({
    if(Get-Process GenshinImpact -ErrorAction SilentlyContinue){Set-Status '游戏已经在运行。进入世界后点「刷新全部数据」。';return}
    Start-Process "$root/Play-Local.cmd" -WorkingDirectory $root -WindowStyle Minimized
    Set-Status '正在启动服务端和游戏（首次加载可能需要几分钟）。进入游戏世界后，管理器会自动读取数据。'
})
$console.Add_Click({Start-Process 'http://127.0.0.1:8088/console'})
$refresh.Add_Click({Invoke-UiAction '正在读取全部数据…' {Read-All;Set-Status '已读取全部数据。'}})
$heal.Add_Click({Invoke-UiAction '正在回血／复活…' {$null=Invoke-LocalGameCommand 'heal';Set-Status '已恢复当前队伍生命并复活倒下角色。'}})
$revert.Add_Click({$script:loadingQty=$true;try{foreach($field in $fields){if($script:loadedQty.ContainsKey($field.key)){$boxes[$field.key].Value=$script:loadedQty[$field.key]}}}finally{$script:loadingQty=$false};Update-QtyDirty;Set-Status '已撤销未应用的修改。'})
$apply.Add_Click({
    $changes=@(Get-QtyChanges);if(!$changes.Count){return}
    $lines=$changes|ForEach-Object {"$($_.label)：$(Format-Number $script:loadedQty[$_.key]) → $(Format-Number $boxes[$_.key].Value)"}
    if(!(Confirm-Action ("将把下列物品设为新的总数量：`n`n"+($lines -join "`n")+"`n`n确定应用？") '确认修改数量')){return}
    Invoke-UiAction '正在应用数量…' {
        $before=Invoke-LocalGameCommand 'status';$before|ConvertTo-Json -Depth 5 -Compress|Add-Content "$root/logs/manager-currency-history.jsonl" -Encoding UTF8
        foreach($field in $changes){$amount=[int]$boxes[$field.key].Value;if($amount -ne [int]$before.($field.key)){$null=Invoke-LocalGameCommand "set $($field.id) $amount"}}
        $null=Read-Current;Set-Status "已应用 $($changes.Count) 项数量修改。"
    }
})
$banners.Add_Click({Invoke-UiAction '正在保存卡池 UP…' {$avatarId=Resolve-ComboId $character '角色';$weaponId=Resolve-ComboId $weapon '武器';$null=Invoke-LocalGameCommand "banner $avatarId $weaponId";$null=Read-Current;Set-Status '已保存 UP。关闭再打开游戏祈愿界面即可查看。'}})
$bannerReset.Add_Click({Set-ComboById $character $script:currentUp.character;Set-ComboById $weapon $script:currentUp.weapon})

if($Check -or $CheckOnline){
    $form.CreateControl();$form.PerformLayout()
    if($boxes.Count -ne 11 -or $tabs.TabPages.Count -ne 6 -or $character.Items.Count -ne @($catalog.avatars | Where-Object stars -eq 5).Count -or $weapon.Items.Count -ne $catalog.weapons.Count){throw 'UI construction failed'}
    foreach($key in $boxes.Keys){$grid=$boxes[$key].Parent;if($labels[$key].Parent -ne $grid -or $grid.GetRow($labels[$key]) -ne $grid.GetRow($boxes[$key])){throw "Label misaligned: $key"}}
    if(!$qty.AutoScroll){throw 'Materials cannot scroll'}
    foreach($name in 'Read-All','Read-Gear','Read-Warehouse','Read-WorldLevel','Get-CheckedGearRequests','Get-WeaponCleanupRequest','Get-ArtifactRequest'){if(!(Get-Command $name -ErrorAction SilentlyContinue)){throw "Missing function $name"}}
    if($CheckOnline){
        if((Get-Command Invoke-LocalGameCommand).CommandType -ne 'Function'){throw 'Command resolution conflict'}
        $snapshot=Read-Current
        foreach($field in $fields){if(!$boxes[$field.key].Enabled -or $boxes[$field.key].Value -ne [decimal]$snapshot.($field.key)){throw "Readback failed: $($field.key)"}}
        if($apply.Enabled){throw 'Fresh readback should have no pending changes'}
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
    'PASS: UI construction, 6 tabs, aligned quantity rows and scroll layout.'
    $form.Dispose();exit
}

# Read automatically on start, then keep trying quietly until the player is in the world.
function Invoke-QuietRead{if($script:online -or $script:busy){return};$script:busy=$true;try{Read-All;Set-Status '已检测到玩家在线，数据已自动读取。'}catch{Set-Connection $false '请启动游戏并进入世界'}finally{$script:busy=$false}}
$autoTimer=New-Object Windows.Forms.Timer;$autoTimer.Interval=8000;$autoTimer.Add_Tick({Invoke-QuietRead})
$form.Add_Shown({Set-Status '正在读取游戏数据…';$form.Refresh();Invoke-QuietRead;if(!$script:online){Set-Status '未检测到在线玩家。启动游戏并进入世界后会自动读取，也可以点「刷新全部数据」。'};$autoTimer.Start()})
$form.Add_FormClosed({$autoTimer.Stop()})
[Windows.Forms.Application]::Run($form)
