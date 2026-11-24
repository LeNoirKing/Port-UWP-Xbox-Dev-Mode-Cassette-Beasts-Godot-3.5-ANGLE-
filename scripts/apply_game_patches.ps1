# Applies Xbox UWP scripts/patches to an extracted CassetteBeasts game directory
# and removes stale .gd.remap / .gdc bytecode for modified scripts.
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$PatchDir = Join-Path $RepoRoot "game_patches"

if (-not (Test-Path (Join-Path $GameDir "project.godot"))) {
    throw "project.godot not found in: $GameDir"
}

$files = Get-ChildItem $PatchDir -Recurse -File
foreach ($file in $files) {
    $rel = $file.FullName.Substring($PatchDir.Length).TrimStart('\', '/')
    $dest = Join-Path $GameDir $rel
    New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
    Copy-Item $file.FullName $dest -Force

    if ($dest.EndsWith(".gd")) {
        $remap = "$dest.remap"
        $gdc = $dest.Substring(0, $dest.Length - 3) + ".gdc"
        if (Test-Path $remap) { Remove-Item $remap -Force }
        if (Test-Path $gdc) { Remove-Item $gdc -Force }
    }
}

# Update project.godot settings for Xbox UWP shader cache & remove GfxMonitor/[logging] if present
$projPath = Join-Path $GameDir "project.godot"
$proj = Get-Content $projPath -Raw
$proj = $proj -replace '(?m)^GfxMonitor=.*\r?\n', ''
$proj = $proj -replace '(?m)^gles3/shaders/shader_cache_size_mb=.*', 'gles3/shaders/shader_cache_size_mb=2048'
$proj = $proj -replace '(?m)^gles3/shaders/shader_compilation_mode=.*', 'gles3/shaders/shader_compilation_mode=2'
$proj = $proj -replace '(?ms)^\[logging\]\r?\n.*?(?=\r?\n\[|\z)', ''
Set-Content -Path $projPath -Value $proj -NoNewline -Encoding UTF8

Write-Output "Patched game directory successfully: $GameDir"
