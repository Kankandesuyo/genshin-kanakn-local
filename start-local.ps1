$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\runtime\Common.ps1"
$cfg = Get-LocalConfig
$java = $cfg.java
if (!$java -or !(Test-Path $java)) { throw 'Java not found. Run Setup.cmd or set "java" in local-config.json.' }
if (!(Test-Path "$root\server\config.json")) { throw 'Not set up yet. Run Setup.cmd first.' }
if (!(Test-Path "$root\server\resources\ExcelBinOutput")) { throw 'Server resources missing; finish extracting resources first.' }
$mongo = Get-ChildItem "$root\runtime" -Filter mongod.exe -Recurse | Select-Object -First 1 -ExpandProperty FullName
if (!$mongo) { throw 'MongoDB runtime is missing.' }
foreach ($dir in @('logs','db')) { New-Item -ItemType Directory -Force "$root\$dir" | Out-Null }
if (!(Get-NetTCPConnection -LocalPort 27018 -State Listen -ErrorAction SilentlyContinue)) {
    $dbProcess = Start-Process -FilePath $mongo -ArgumentList @('--dbpath', "`"$root\db`"", '--bind_ip', '127.0.0.1', '--port', '27018', '--logpath', "`"$root\logs\mongodb.log`"", '--logappend') -WindowStyle Hidden -PassThru
    $dbProcess.Id | Set-Content "$root\logs\mongodb.pid"
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        if (Get-NetTCPConnection -LocalPort 27018 -State Listen -ErrorAction SilentlyContinue) { break }
        if ($dbProcess.HasExited) { throw 'MongoDB exited. Check logs/mongodb.log.' }
        Start-Sleep -Seconds 1
    }
}
if (!(Get-NetTCPConnection -LocalPort 8088 -State Listen -ErrorAction SilentlyContinue)) {
    if (Test-Path "$root\logs\server.pid") {
        $existing = Get-Process -Id ([int](Get-Content "$root\logs\server.pid")) -ErrorAction SilentlyContinue
        if ($existing -and $existing.Path -eq $java) { Write-Host 'Server is already starting.'; exit }
    }
    $serverProcess = Start-Process -FilePath $java -ArgumentList @('-Xms512m','-Xmx4g','-cp','local-gacha.jar;grasscutter.jar','emu.grasscutter.Grasscutter') -WorkingDirectory "$root\server" -WindowStyle Hidden -RedirectStandardOutput "$root\logs\server.stdout.log" -RedirectStandardError "$root\logs\server.stderr.log" -PassThru
    $serverProcess.Id | Set-Content "$root\logs\server.pid"
}
Write-Host 'Local server starting. Console: http://127.0.0.1:8088/console'
Write-Host 'Credentials: credentials.local.json. Main log: server/logs/latest.log'
