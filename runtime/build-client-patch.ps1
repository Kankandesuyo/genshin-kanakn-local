$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$toolchain = "$root\rust-toolchain"
# Set VCVARS to your Visual Studio vcvars64.bat path.
$vcvars = if ($env:VCVARS) { $env:VCVARS } else { 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat' }
$compilerVariables = & cmd.exe /d /c "call `"$vcvars`" >nul && set"
if ($LASTEXITCODE -ne 0) { throw 'MSVC environment initialization failed.' }
foreach ($line in $compilerVariables) {
    if ($line -match '^(PATH|LIB|LIBPATH|INCLUDE|VCINSTALLDIR|VCToolsInstallDir|VSINSTALLDIR|WindowsSdkDir|WindowsSDKVersion|WindowsSDKLibVersion|UCRTVersion|UniversalCRTSdkDir)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process')
    }
}
$env:PATH = "$toolchain\bin;$env:PATH"
$env:RUSTC = "$toolchain\bin\rustc.exe"
$env:CARGO_HOME = "$root\cargo-home"
$env:CARGO_NET_OFFLINE = 'true'
Push-Location "$root\animegamepatch-master"
try {
    & "$toolchain\bin\cargo.exe" build --release --locked --offline
    if ($LASTEXITCODE -ne 0) { throw 'Patch compilation failed.' }
} finally { Pop-Location }
