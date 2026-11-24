# Development Diary — *Cassette Beasts* Xbox Series S UWP Port (Godot 3.5 + ANGLE)

**Packaged version:** `1.2.0.49` (`x64`, `godot.uwp.exe` + ANGLE D3D11).

---

## 1. Base Architecture

*Cassette Beasts* runs on **Godot Engine 3.5** compiled for **UWP (`Windows.Universal`)**, translating **OpenGL ES 3.0** calls to **Direct3D 11** via **ANGLE**:
- On PC UWP it runs on `Intel(R) UHD Graphics Direct3D11 vs_5_0 ps_5_0`.
- On Xbox Series S it runs on `SraKmd_arden Direct3D11 vs_5_0 ps_5_0`.

Most of the issues encountered stem from strict differences between native OpenGL ES 3.0 and the **ANGLE → Direct3D 11** translation layer on the `SraKmd_arden` driver.

---

## 2. Bugs Found and Fixes Applied

### A. UWP Initialization, GLES3, and ANGLE Compatibility

| Issue | Root Cause | Fix Applied | File(s) |
| :--- | :--- | :--- | :--- |
| GLES3 fallback/failure on UWP startup | `OS_UWP::initialize` did not explicitly set `GLES_3_0` in the main branch, and `detect.py` forced rebuilding ANGLE with an older toolset | Default to `ContextEGL_UWP::GLES_3_0` (with fallback warning to GLES2) and support `ANGLE_PREBUILT` | `platform/uwp/os_uwp.cpp`, `platform/uwp/detect.py` |
| ANGLE errors/crashes from unbound UBOs | ANGLE rejects draw calls with `GL_UNIFORM_BUFFER` slots bound to `0` | Created a zeroed 64 KB `dummy_ubo` on `RasterizerStorageGLES3` init, bound across slots `0..7` and used when unbinding in canvas/scene/particles | `drivers/gles3/rasterizer_storage_gles3.cpp`, `rasterizer_canvas_base_gles3.cpp`, `rasterizer_scene_gles3.cpp` |
| Compressed textures rejected by ANGLE | ANGLE D3D11 rejects compressed textures whose dimensions are not multiples of 4 | Set `is_npot_repeat_mipmap = true` when `(p_width % 4) != 0 \|\| (p_height % 4) != 0` under `ANGLE_ENABLED` | `drivers/gles3/rasterizer_storage_gles3.cpp` |
| Washed-out colors / incorrect sRGB space | Missing sRGB→linear conversion on albedo textures under ANGLE when `FLAG_CONVERT_TO_LINEAR` is not set | Enable sRGB conversion in generated shader code when `ANGLE_ENABLED` and the texture does not convert to linear | `scene/resources/material.cpp` |
| Virtual keyboard and cache path on Xbox UWP | `InputPane::GetForCurrentView()` can throw or return `nullptr`, and `get_cache_path()` was missing | Detect `DeviceFamily == "Windows.Xbox"` in `has_virtual_keyboard()`, guard `show/hide_virtual_keyboard()` with `try/catch`, and redirect `get_cache_path()` to `get_user_data_dir()` | `platform/uwp/os_uwp.cpp` |

---

### B. 3D Rendering and Visual Bugs

| Issue | Root Cause | Fix Applied | File(s) |
| :--- | :--- | :--- | :--- |
| Corrupted / black **Depth of Field (DoF)** | ANGLE D3D11 fails when the target FBO keeps `GL_DEPTH_ATTACHMENT` attached while sampling the same depth buffer on `GL_TEXTURE1`, or when depth sampler parameters are not `GL_NEAREST` / `GL_CLAMP_TO_EDGE` | Temporarily detach `GL_DEPTH_ATTACHMENT` on `mip_maps[0].sizes[0].fbo` and `current_rt->fbo` during DoF/SSS/SSAO passes and force `GL_TEXTURE_COMPARE_MODE=GL_NONE`, `GL_NEAREST`, `GL_CLAMP_TO_EDGE`, and base/max level `0..0` on `GL_TEXTURE1` | `drivers/gles3/rasterizer_scene_gles3.cpp` |
| Water creature particles invisible/broken | GPU `Particles` (Transform Feedback) issues in `Swimmer.tscn` under ANGLE | Converted `Swimmer.tscn` emitters from `Particles` to `CPUParticles` | `game_patches/world/monsters/Swimmer.tscn` |
| Incorrect draw/depth order on cutout/transparent objects (Brightside Pier carousel, sand ripples, trees, NPCs) | Standard `depth_prepass` interacted poorly with certain opaque materials vs `DEPTH_DRAW_ALPHA_PREPASS` | Restricted `depth_prepass` to `DEPTH_DRAW_ALPHA_PREPASS` only (excluding shadow pass), with `glEnable(GL_POLYGON_OFFSET_FILL)` and `glPolygonOffset(0.0f, 4.0f)` | `drivers/gles3/rasterizer_scene_gles3.cpp` |
| **Grass flickering and collapsing into a rectangle** | 1) `GrassParticles.tscn` used `draw_order = 2` (`VIEW_DEPTH`), forcing `glMapBufferRange` + CPU sorting every frame despite using `ALPHA_SCISSOR = 0.98`.<br>2) `lifetime = 1.0` with `explosiveness = 1.0` restarted Transform Feedback every second, desynchronizing on `SraKmd_arden`.<br>3) Stale `.gd.remap` files forced loading old `.gdc` bytecode instead of modified `.gd` scripts. | 1) Set `draw_order = 0` in `GrassParticles.tscn`.<br>2) Set `lifetime = 86400.0` in `GrassParticles.gd` to avoid 1-second restarts (`MultiMeshInstance` and `SurfaceTool` were also tested, but `INSTANCE_MULTIMESH` failed on Xbox `SraKmd_arden` like `Swimmer` and `SurfaceTool` hid the mesh; `Particles` + `lifetime = 86400.0` was verified clean on PC UWP).<br>3) Delete stale `.gd.remap` and `.gdc` files when applying patches. | `game_patches/world/objects/grass/GrassParticles.tscn`, `game_patches/world/objects/grass/GrassParticles.gd`, `scripts/apply_game_patches.ps1` |

---

### C. Shader Compilation, Cache, and Load Times

1. **Key diagnostic from logs (`godot.log`):**
   - `Async. shader compilation: OFF (enabled for project, but not supported)`: ANGLE on Direct3D 11 under UWP does not support `KHR_parallel_shader_compile`, so all shader compilation runs **synchronously** on the main thread.
2. **Unlocking `ShaderCacheGLES3` without async compilation:**
   - In stock Godot 3.5, `ShaderCacheGLES3` only activated if `async shader compilation` was active. Decoupled this check in `drivers/gles3/rasterizer_storage_gles3.cpp` so `Shader cache: ON` whenever `program_binary_supported` is true.
3. **Bundled precompiled cache (`res://shader_cache/`):**
   - Integrated **269 precompiled Xbox shader binaries** (`200.2 MB`) and added read-only fallback to `res://shader_cache/<hash>` in `drivers/gles3/shader_cache_gles3.cpp`.
4. **32-bit integer overflow fix & 2 GB cache limit:**
   - In `drivers/gles3/shader_cache_gles3.cpp`, `(int)GLOBAL_GET(...) * 1024 * 1024` overflowed at `2048 MB`. Fixed to `(uint64_t)(int)GLOBAL_GET(...) * 1024ULL * 1024ULL` and set `gles3/shaders/shader_cache_size_mb=2048` in `project.godot`.
5. **Expanded startup preloading (`ShaderCache.gd`):**
   - Increased `shaders_per_frame = 64` and added battle VFX/scene preloading.

---

### D. Zone Streaming and CPU Threading

1. **Streaming queues:**
   - `InstanceQueue.gd`: switched to a **5 ms per-frame** budget.
   - `ResourceQueue.gd`: increased `MAX_DELAY = {false: 8, true: 120}`.
   - `LevelStreamer.gd` / `LevelStreamerSettings.gd`: adjusted `instance_margin = 36.0` and margins `14 / 18 / 28`.
2. **Thread pool for resource loading (`JobQueue.gd` / `ResourceQueueThreaded.gd`):**
   - Refactored `JobQueue.gd` to support configurable `thread_count` (`1` by default to keep `UserSettings.gd` file I/O sequential) using `jobs.pop_front()` per `sem.wait()`.
   - Configured `ResourceQueueThreaded.gd` with `thread_count = 4`.
3. **Documented Godot 3.5 UWP threading limitation:**
   - In `platform/uwp/os_uwp.cpp`, separate-thread rendering is disabled (`VisualServerWrapMT(visual_server, false)`), so main logic, scene instantiation, and ANGLE/D3D11 draw calls run on a single main thread (plus 1 XAudio2 audio thread and the `JobQueue`/`ResourceQueueThreaded` worker threads).

---

### E. UI, UWP Icons, and Final Packaging

- Removed `GfxMonitor` autoload and `[logging]` section from `project.godot`.
- Hid non-functional UWP store/DLC buttons in `TitleMenu.gd`.
- Updated all square logos (`StoreLogo`, `Square44x44Logo`, `Square71x71Logo`, `Square150x150Logo`, `Square310x310Logo` and `.scale-100`) and rectangular logos (`SplashScreen` `620×300`, `Wide310x150Logo` `310×150`).
- Configured manifest with `DisplayName="Cassette Beasts"` (`v1.2.0.49`) and packaged/signed with `makeappx.exe` + `signtool.exe` using a development `.pfx` certificate.
