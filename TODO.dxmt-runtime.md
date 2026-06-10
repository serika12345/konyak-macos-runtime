# Konyak macOS DXMT Runtime TODO

Goal: make Konyak's macOS runtime use a CrossOver-derived Wine by default, keep
DXVK usable without GPTK, and add DXMT/GPTK components as explicitly selected
backends instead of implicit runtime overwrites.

## Decisions

- CrossOver-derived Wine is the default macOS Wine runtime source.
- DXVK, DXMT, and GPTK/D3DMetal are manually selected and mutually exclusive.
- Konyak will not implement CrossOver's `cxcompatdb` runtime auto-selection.
- GPTK/D3D12 support keeps the `ntdll.__wine_unix_call` compatibility
  requirement.
- DXMT is built by Konyak from FOSS sources with Nix before enabling Actions.
- GPTK binaries remain user-imported and are not distributed from this repo.

## Runtime Layout Target

```text
runtime/
  bin/wine
  bin/wine64
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
      x86_64-windows/winemetal.dll
      x86_64-unix/winemetal.so
    gptk-d3dmetal/
```

## Implementation Checklist

- [x] Build and package CrossOver-derived Wine in Konyak runtime layout.
- [x] Add a Wine32-on-64 launch smoke that runs the runtime's 32-bit
      `cmd.exe` against an assembled Konyak runtime stack.
- [ ] Ensure local `macos-vulkan-wine-smoke` passes with that Wine.
- [ ] Add a Nix DXMT package that builds locally on macOS before Actions.
- [ ] Require `KONYAK_METAL_TOOLCHAIN_BIN` for DXMT builds because Apple's
      Metal compiler is delivered by Xcode outside the Nix store.
- [x] Verify DXMT output contains x86_64 `winemetal.so` plus both x86_64 and
      i386 `winemetal.dll`, `d3d11.dll`, `dxgi.dll`, and `d3d10core.dll`.
- [ ] Add Wine-side DXMT prerequisites if the package requires hidden
      `winemac.drv` API exports.
- [ ] Keep DXVK packaging independent and usable without GPTK.
- [ ] Change Konyak installer behavior so GPTK import never overwrites
      `lib/wine/*` directly.
- [ ] Add backend enum support in Konyak CLI/UI:
      `wine`, `dxvk`, `dxmt`, `gptkD3DMetal`.
- [ ] Add backend-specific `WINEDLLPATH`, `WINEDLLOVERRIDES`, and
      `DYLD_LIBRARY_PATH` generation.
- [ ] Add local probes:
      - Vulkan/MoltenVK smoke for DXVK base.
      - `ntdll.__wine_unix_call` export check for GPTK.
      - DXMT DLL load probe.
      - GPTK D3D12/DXGI DLL load probe.
- [ ] Add GitHub Actions only after local Nix DXMT builds pass.

## Current Known Constraints

- `nixpkgs-unstable` no longer exposes `llvmPackages_15`.
- DXMT currently documents LLVM 15 as the expected LLVM version.
- DXMT cross build needs a Wine install/build path and a Windows cross compiler.
- Xcode 26+ can require `xcodebuild -downloadComponent MetalToolchain` before
  `xcrun -sdk macosx metal` works.
- DXMT now builds both x86_64 and i386 Windows DLLs. The Unix-side
  `winemetal.so` remains x86_64 because the runtime is Wine32-on-64 and has no
  i386 Unix host path.
