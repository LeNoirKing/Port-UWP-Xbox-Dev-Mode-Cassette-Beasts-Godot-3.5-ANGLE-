# Cassette Beasts — Xbox Series and Xbox One Dev Mode UWP Port (Godot 3.5 + ANGLE)

This repository contains **only the engine patches, modified game scripts, build/packaging tools, UWP export templates, and technical dev diary** required to run *Cassette Beasts* on Xbox in Dev Mode (UWP / `Windows.Universal`) using Godot 3.5 + ANGLE (OpenGL ES 3.0 → Direct3D 11).

> **Legal notice:** No copyrighted *Cassette Beasts* assets, full scenes, or proprietary game binaries are included. You need your own legally owned, locally extracted copy of the game.

---

## Repository Structure

- `patches/godot_uwp_xbox.patch` — Full patch on top of Godot 3.5 (`patches/godot_base_commit.txt`) for GLES3/ANGLE compatibility, `res://shader_cache/` fallback, DoF fixes, selective `depth_prepass`, and Xbox UWP support.
- `GODOT/build_xbox_uwp_template.ps1` — Script to clone ANGLE (`uwp-2017`), build it with MSBuild, and build `godot.uwp.exe` with SCons.
- `GODOT/templates/` — Prebuilt UWP GLES3 export templates (`uwp_x64_debug.zip`, `uwp_x64_release.zip`).
- `game_patches/` — Modified game scripts and scenes (`JobQueue.gd`, `ResourceQueueThreaded.gd`, `InstanceQueue.gd`, `ResourceQueue.gd`, `ShaderCache.gd`, `LevelStreamer.gd`, `LevelStreamerSettings.gd`, `GrassParticles.gd`, `GrassParticles.tscn`, `Swimmer.tscn`, `TitleMenu.gd`).
- `scripts/apply_game_patches.ps1` — Applies `game_patches/`, removes stale `.gd.remap` / `.gdc` files, and updates `project.godot` settings.
- `scripts/package_uwp.ps1` — Packs with `makeappx.exe` and signs with `signtool.exe`.
- `scripts/AppxManifest.template.xml` — UWP manifest template (`Windows.Universal`, `x64`).
- `DEV_DIARY.md` — Full technical dev diary documenting bugs found and fixes applied (in Spanish).

---

## Prerequisites

- Windows 10/11 with **Visual Studio 2022/2026** (*Universal Windows Platform development* workload + UWP C++ tools).
- **Windows SDK 10.0.26100.0** (provides `makeappx.exe` and `signtool.exe`).
- **Python 3** + **SCons** (`pip install scons`) + **Git**.
- Locally extracted copy of *Cassette Beasts* (folder containing `project.godot`).

---

## Step-by-Step Build & Packaging Guide

### 1. Clone Godot 3.5 and apply the engine patch
*(Skip steps 1–2 if you use the prebuilt templates in `GODOT/templates/`).*
```powershell
git clone https://github.com/godotengine/godot.git GODOT\godot
cd GODOT\godot
git checkout (Get-Content ..\..\patches\godot_base_commit.txt)
git apply ..\..\patches\godot_uwp_xbox.patch
```

### 2. Build ANGLE and `godot.uwp.exe`
```powershell
powershell -ExecutionPolicy Bypass -File GODOT\build_xbox_uwp_template.ps1 -Arch x64
```
This builds the UWP executable (`godot.uwp.exe`) and ANGLE DLLs (`libEGL.dll`, `libGLESv2.dll`).

### 3. Prepare the UWP staging folder and patch the game
1. Copy `godot.uwp.exe`, `libEGL.dll`, `libGLESv2.dll`, `AppxManifest.template.xml` (renamed to `AppxManifest.xml`), and your `Assets\` folder into a staging directory (e.g., `C:\temp\cb_staging\`).
2. Copy the extracted game contents into `C:\temp\cb_staging\game\`.
3. Apply the script patches and remove stale `.gd.remap` / `.gdc` bytecode files:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\apply_game_patches.ps1 -GameDir "C:\temp\cb_staging\game"
```
4. *(Optional)* If you have a precompiled Xbox shader cache, place it in `C:\temp\cb_staging\game\shader_cache\`.

### 4. Create a dev certificate, pack, and sign the `.appx`
```powershell
$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=ExampleUser" -KeyUsage DigitalSignature -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3","2.5.29.19={text}")
$pwd = ConvertTo-SecureString -String "example-password" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "dev_cert_example.pfx" -Password $pwd

powershell -ExecutionPolicy Bypass -File scripts\package_uwp.ps1 `
    -StagingDir "C:\temp\cb_staging" `
    -OutputAppx "Cassette Beasts.appx" `
    -PfxPath "dev_cert_example.pfx" `
    -PfxPassword "example-password"
```

### 5. Install on Xbox Series S (Dev Mode)
1. Upload `Cassette Beasts.appx` through **Xbox Device Portal** (`Add` → select the `.appx`).
2. In the Device Portal's installed apps list, change the app type from **App** to **Game** to grant full UWP game resource allocation.
