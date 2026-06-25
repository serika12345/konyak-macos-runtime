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

## Remaining Work

- Investigate and add Wine-side DXMT prerequisites if the package requires
  hidden `winemac.drv` API exports.
- Add backend enum support in the parent Konyak CLI/UI:
  `wine`, `dxvk`, `dxmt`, `gptkD3DMetal`.
- Add MoltenVK/Vulkan smoke after the Direct3D backend probes are stable.

## Runtime Smoke CI Expectations

These checks care about runtime behavior, not binary identity with CrossOver.
Keep jobs narrow so a failed backend smoke can be rerun without rebuilding the
Wine runtime or unrelated components.

- Keep release payload checks for Wine32-on-64, DXVK, DXMT, vkd3d, GStreamer,
  addon payloads, and winetricks.
- Keep assembled runtime launch smoke for 32-bit `cmd.exe`.
- Keep assembled runtime GUI launch smoke for the normal
  `wineloader start /unix <program>` path.
- Keep backend smoke runners on temporary prefixes and selected runtime backend
  directories. They must not copy backend DLLs into the prefix.
- Keep GPTK/D3DMetal smoke as CI-only external-payload workflow coverage. The
  pinned Gcenx payload may be downloaded only into runner-local temporary
  storage, imported only into the unpacked smoke runtime, and excluded from
  release archives and workflow artifacts.

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
