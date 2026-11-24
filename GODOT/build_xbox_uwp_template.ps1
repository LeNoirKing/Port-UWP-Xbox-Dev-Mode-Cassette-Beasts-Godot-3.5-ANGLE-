# Builds Godot 3.5 UWP export templates (GLES3 via ANGLE -> Direct3D 11) for Xbox Series / Windows.
# Requirements: Visual Studio 2022/2026 with "Universal Windows Platform development" + C++ UWP tools, Python + SCons, git.
# Usage: powershell -File build_xbox_uwp_template.ps1 [-Arch x64] [-SkipBuild]
param(
    [ValidateSet("x64", "x86")][string]$Arch = "x64",
    [string]$VsPath = "C:\Program Files\Microsoft Visual Studio\18\Community",
    [string]$ToolSet = "v145",
    [string]$SdkVersion = "10.0.26100.0",
    [switch]$SkipBuild
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$GodotDir = "$Root\godot"
$AngleDir = "$Root\angle"
$OutDir = "$Root\templates"
$vcvars = "$VsPath\VC\Auxiliary\Build\vcvarsall.bat"
$msbuild = "$VsPath\MSBuild\Current\Bin\amd64\MSBuild.exe"
$angleOut = "$AngleDir\winrt\10\src\Release_$(if ($Arch -eq 'x64') {'x64'} else {'Win32'})"

if (-not $SkipBuild) {
    # ANGLE (uwp-2017 branch has the WinRT projects); retargeted to the installed toolset.
    if (-not (Test-Path "$AngleDir\winrt\10\src\angle.sln")) {
        git clone --depth 1 --branch uwp-2017 https://github.com/microsoft/angle.git $AngleDir
    }
    $env:CL = "/wd4996"
    $plat = if ($Arch -eq 'x64') { 'x64' } else { 'Win32' }
    & $msbuild "$AngleDir\winrt\10\src\angle.sln" /nologo /v:m /m /p:Configuration=Release /p:Platform=$plat `
        /p:PlatformToolset=$ToolSet /p:WindowsTargetPlatformVersion=$SdkVersion /p:SDLCheck=false
    if ($LASTEXITCODE -ne 0) { throw "ANGLE build failed" }
    Remove-Item Env:\CL

    $env:ANGLE_SRC_PATH = $AngleDir
    $env:ANGLE_PREBUILT = "1"
    foreach ($target in @("release_debug", "release")) {
        cmd /c "`"$vcvars`" $Arch uwp $SdkVersion >nul && cd /d `"$GodotDir`" && scons platform=uwp target=$target tools=no -j$env:NUMBER_OF_PROCESSORS"
        if ($LASTEXITCODE -ne 0) { throw "scons failed for $target" }
    }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$builds = @{ debug = "opt.debug"; release = "opt" }
foreach ($kind in $builds.Keys) {
    $stage = Join-Path $env:TEMP "godot_uwp_$kind"
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $stage | Out-Null

    Copy-Item "$GodotDir\misc\dist\uwp_template\Assets" $stage -Recurse
    # The manifest references logos without the ".scale-100" qualifier.
    Get-ChildItem "$stage\Assets\*.scale-100.png" | ForEach-Object { Copy-Item $_.FullName ($_.FullName -replace '\.scale-100', '') }
    Copy-Item "$Root\xbox\AppxManifest.xml" $stage
    $exe = Get-ChildItem "$GodotDir\bin" -Filter "godot.uwp.$($builds[$kind]).*.$Arch.exe" | Select-Object -First 1
    if (-not $exe) { throw "Missing $kind binary in $GodotDir\bin" }
    Copy-Item $exe.FullName "$stage\godot.uwp.exe"
    foreach ($dll in "libEGL.dll", "libGLESv2.dll") { Copy-Item "$angleOut\$dll" $stage }

    $zip = "$OutDir\uwp_${Arch}_$kind.zip"
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path "$stage\*" -DestinationPath $zip
    Write-Host "Template created: $zip"
}
Write-Host "Install: copy the zips to %APPDATA%\Godot\templates\3.5.stable\ or use them as Custom Template in the UWP export preset."
