# Konyak macOS DXMT Runtime TODO

Goal: make Konyak's macOS runtime use a CrossOver-derived Wine by default, keep
DXVK usable without GPTK, and add DXMT/GPTK components as explicitly selected
backends instead of implicit runtime overwrites.

See `docs/crossover-runtime-compatibility.md` for the broader compatibility
plan covering the CrossOver/nixpkgs comparison, GnuTLS and dlopen-facing dylib
placement, the public single-archive distribution decision, and the phased
normal-Wine-compatibility repair.

## Decisions

- CrossOver-derived Wine is the default macOS Wine runtime source.
- DXVK, DXMT, and GPTK/D3DMetal are manually selected and mutually exclusive.
- Konyak will not implement CrossOver's `cxcompatdb` runtime auto-selection.
- GPTK/D3D12 support keeps the `ntdll.__wine_unix_call` compatibility
  requirement.
- DXMT is built by Konyak from FOSS sources with Nix before enabling Actions.
- GPTK binaries remain user-imported and are not distributed from this repo.
- Public macOS runtime releases should expose a single assembled runtime stack
  archive. Separate Wine, DXMT, DXVK, vkd3d, MoltenVK, GStreamer, FreeType,
  wine-mono, wine-gecko, and winetricks artifacts remain internal CI units for
  focused rebuild, verification, and rerun behavior.

## Runtime Layout Target

```text
runtime/
  bin/wine
  bin/wineloader
  lib/wine/i386-windows/...
  lib/wine/x86_64-windows/...
  lib/wine/x86_64-unix/...
  components/
    dxvk/
      i386-windows/d3d9.dll
      i386-windows/d3d10.dll
      i386-windows/d3d10_1.dll
      i386-windows/d3d10core.dll
      i386-windows/d3d11.dll
      i386-windows/dxgi.dll
      x86_64-windows/d3d9.dll
      x86_64-windows/d3d10.dll
      x86_64-windows/d3d10_1.dll
      x86_64-windows/d3d10core.dll
      x86_64-windows/d3d11.dll
      x86_64-windows/dxgi.dll
    dxmt/
      i386-windows/d3d11.dll
      i386-windows/dxgi.dll
      i386-windows/d3d10core.dll
      i386-windows/winemetal.dll
      x86_64-windows/d3d11.dll
      x86_64-windows/dxgi.dll
      x86_64-windows/d3d10core.dll
      x86_64-windows/nvapi64.dll
      x86_64-windows/nvngx.dll
      x86_64-windows/winemetal.dll
      x86_64-unix/winemetal.so
    gptk-d3dmetal/
      lib/external/D3DMetal.framework
      lib/external/libd3dshared.dylib
      lib/wine/x86_64-windows/d3d11.dll
      lib/wine/x86_64-windows/d3d12.dll
      lib/wine/x86_64-windows/dxgi.dll
      lib/wine/x86_64-windows/nvapi64.dll
      lib/wine/x86_64-windows/nvngx.dll
      lib/wine/x86_64-unix/...
```

## Implementation Checklist

- [x] Build and package CrossOver-derived Wine in Konyak runtime layout.
- [x] Add a Wine32-on-64 launch smoke that runs the runtime's 32-bit
      `cmd.exe` against an assembled Konyak runtime stack.
- [x] Add a Nix DXMT package that builds locally on macOS before Actions.
- [x] Require `KONYAK_METAL_TOOLCHAIN_BIN` for DXMT builds because Apple's
      Metal compiler is delivered by Xcode outside the Nix store.
- [x] Verify DXMT output contains x86_64 `winemetal.so` plus both x86_64 and
      i386 `winemetal.dll`, `d3d11.dll`, `dxgi.dll`, and `d3d10core.dll`.
- [x] Verify DXMT output contains x86_64 NVIDIA shim DLLs `nvapi64.dll` and
      `nvngx.dll` while keeping the i386 DXMT payload limited to the existing
      DXMT DLL set.
- [ ] Add Wine-side DXMT prerequisites if the package requires hidden
      `winemac.drv` API exports.
- [x] Publish the default macOS runtime as one assembled stack archive while
      retaining separate component artifacts inside CI.
- [x] Keep DXVK packaging independent and usable without GPTK.
      The current `dxvk-macos` component combines the pinned Gcenx DXVK-macOS
      DLLs with upstream DXVK `v1.10.3` only for missing `d3d10.dll` and
      `d3d10_1.dll`, and is checked by `scripts/check-dxvk-component.zsh`.
- [x] Package GStreamer plugins and `gst-plugin-scanner` with the macOS runtime
      so Wine media handling does not depend on host GStreamer plugins.
      The current `gstreamer` component includes representative core,
      playback/typefind, MP4/WAV, and Apple media plugin dylibs under
      `lib/gstreamer-1.0`, includes `libexec/gstreamer-1.0/gst-plugin-scanner`,
      and is checked by `scripts/check-gstreamer-component.zsh`.
- [x] Align GPTK/D3DMetal NVIDIA shim import with CrossOver 26.1.
      The import contract now accepts CrossOver.app's `apple_gptk` payload,
      requires `nvapi64` and canonical `nvngx` files, normalizes older
      `nvngx-on-metalfx` source names, and keeps GPTK/D3DMetal D3D10 out of
      the required payload because D3D10 is owned by DXVK/DXMT components.
- [x] Add CrossOver-derived vkd3d as a runtime component.
      The component is built from the pinned CrossOver FOSS source archive,
      reuses the Wine runtime artifact for `widl`, ships both i386 and x86_64
      `libvkd3d-1.dll`, `libvkd3d-shader-1.dll`, and
      `libvkd3d-utils-1.dll`, and is checked by
      `scripts/check-vkd3d-component.zsh`.
- [x] Change Konyak installer behavior so GPTK import never overwrites
      `lib/wine/*` directly. User-imported GPTK/D3DMetal now installs under
      `components/gptk-d3dmetal`, and macOS runtime reinstall/update preserves
      and migrates the user-provided component instead of replacing it with the
      base Wine payload.
- [x] Add a Konyak-owned minimal GPTK/D3DMetal loader shim at
      `lib/wine/x86_64-unix/cxcompatdb.so`. The shim uses only CrossOver Wine's
      public `ntdll` exports to prepend the user-imported GPTK Wine root and
      set the native D3DMetal load order. It does not implement CrossOver's
      proprietary compatibility database or title-specific patch behavior.
- [ ] Add backend enum support in Konyak CLI/UI:
      `wine`, `dxvk`, `dxmt`, `gptkD3DMetal`.
- [x] Add backend-specific `WINEDLLPATH`, `WINEDLLOVERRIDES`, and
      `DYLD_LIBRARY_PATH` generation.
- [x] Add GitHub Actions only after local Nix DXMT builds pass.

## Runtime Smoke CI Checklist

These checks care about runtime behavior, not binary identity with CrossOver.
Keep jobs narrow so a failed backend smoke can be rerun without rebuilding the
Wine runtime or unrelated components.

- [x] Keep release payload checks for Wine32-on-64, DXVK, DXMT, vkd3d, and
      GStreamer.
- [x] Keep assembled runtime launch smoke for 32-bit `cmd.exe`.
- [x] Keep assembled runtime GUI launch smoke for the normal
      `wineloader start /unix <program>` path.
- [x] Add headless Windows probe executables built with mingw inside the
      runtime submodule.
      - [x] D3D11 device smoke for DXVK.
      - [x] D3D11 device smoke for DXMT.
      - [x] D3D12 device smoke for vkd3d.
      - [x] Win32 GUI launch smoke sentinel probe.
- [x] Add backend smoke runner scripts that create a temporary `WINEPREFIX`,
      launch probes from the selected runtime backend directory, apply
      backend-specific `WINEDLLPATH`, `WINEPATH`, and `WINEDLLOVERRIDES`,
      enforce a timeout, and print diagnostics on failure.
- [x] Add runtime Actions jobs for each backend smoke after artifact assembly:
      `smoke-dxvk-d3d11`, `smoke-dxmt-d3d11`, and `smoke-vkd3d-d3d12`.
- [ ] Add MoltenVK/Vulkan smoke after the Direct3D backend probes are stable.
- [x] Keep GPTK/D3DMetal smoke as CI-only external-payload workflow coverage.
      The workflows download the pinned Gcenx Game Porting Toolkit release
      asset into runner-local temporary storage, verify its SHA-256, import it
      only into the unpacked smoke runtime, and reject runtime release archives
      that contain GPTK/D3DMetal payload paths.
      - [x] `ntdll.__wine_unix_call` compatibility exercised through GPTK
            D3DMetal device smokes on supported hosts, with GitHub hosted
            macOS paravirtual GPU runs accepting only D3DMetal's explicit
            unsupported-host signature.
      - [x] GPTK D3D11/DXGI device smoke.
      - [x] GPTK D3D12/DXGI device smoke.
      - [x] Local `nix run .#gptk-d3dmetal-local-smoke` entry point that copies
            or extracts a runtime into transient storage, imports the pinned
            Gcenx payload only into that copy, and runs both GPTK smoke probes.

## Current Known Constraints

- DXMT currently uses the repository's LLVM 15 input because upstream DXMT
  expects LLVM 15.
- DXMT cross build needs a Wine install/build path and a Windows cross compiler.
- Xcode 26+ can require `xcodebuild -downloadComponent MetalToolchain` before
  `xcrun -sdk macosx metal` works.
- DXMT now builds both x86_64 and i386 Windows DLLs. The Unix-side
  `winemetal.so` remains x86_64 because the runtime is Wine32-on-64 and has no
  i386 Unix host path.
- DXMT's NVIDIA compatibility shim DLLs are currently x86_64-only in the
  Konyak component because the CrossOver comparison target only ships
  `nvapi64.dll` and `nvngx.dll` under the x86_64 DXMT path.
