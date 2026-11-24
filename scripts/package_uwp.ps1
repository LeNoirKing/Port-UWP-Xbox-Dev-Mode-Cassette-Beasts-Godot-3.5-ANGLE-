# Packs and signs the UWP staging folder into an .appx package.
param(
    [Parameter(Mandatory = $true)]
    [string]$StagingDir,
    [string]$OutputAppx = "Cassette Beasts.appx",
    [Parameter(Mandatory = $true)]
    [string]$PfxPath,
    [Parameter(Mandatory = $true)]
    [string]$PfxPassword,
    [string]$SdkBin = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
)

$ErrorActionPreference = "Stop"
& "$SdkBin\makeappx.exe" pack /d $StagingDir /p $OutputAppx /o
if ($LASTEXITCODE -ne 0) { throw "makeappx failed" }

& "$SdkBin\signtool.exe" sign /fd SHA256 /a /f $PfxPath /p $PfxPassword $OutputAppx
if ($LASTEXITCODE -ne 0) { throw "signtool failed" }

Write-Output "Successfully packed and signed: $OutputAppx"
