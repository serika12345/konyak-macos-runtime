# Konyak macOS Runtime

Build recipes and release automation for the Konyak-managed macOS Wine runtime.

This repository builds a Wine runtime from CodeWeavers-published CrossOver FOSS
source archives. It does not mirror or redistribute the proprietary CrossOver
application, bottle manager, branding, or Apple D3DMetal/GPTK binaries.

The produced runtime archives are intended to be consumed by Konyak through
`install-macos-wine --source-manifest`.

## Current Source

The pinned CrossOver source is tracked in `sources/crossover.json`.

## Build

On macOS:

```sh
nix build .#packages.x86_64-darwin.konyak-macos-wine-runtime -L
```

GitHub Actions runs the same build on GitHub-hosted Intel macOS and builds the
`x86_64-darwin` package explicitly. This matches CrossOver's macOS Wine runtime
layout, including `lib/wine/i386-windows`, `lib/wine/x86_64-windows`, and
`lib/wine/x86_64-unix`. The runtime uses Wine32-on-64 for 32-bit Windows
executables; `lib/wine/i386-unix` is not expected.

Local default builds may follow the host architecture, but release artifacts
must use the explicit `x86_64-darwin` package above so the parent Konyak
repository can validate one runtime layout from the submodule-produced
artifact.

DXMT additionally needs Apple's Metal Toolchain, which is provided by Xcode
outside the Nix store. Before building DXMT locally:

```sh
xcodebuild -downloadComponent MetalToolchain
export KONYAK_METAL_TOOLCHAIN_BIN="$(dirname "$(/usr/bin/xcrun -sdk macosx -find metal)")"
nix build --impure .#packages.x86_64-darwin.konyak-macos-dxmt -L
```

## Release Contract

Runtime archives must include:

- `Licenses/`
- `SOURCE.txt`
- `build-info.json`
- Wine32-on-64 payload for 32-bit Windows executables
- a Konyak-compatible runtime stack source manifest

The public release manifest points each component record at one assembled
runtime stack archive. The component archives remain internal CI build and
verification units:

- CrossOver-derived Wine runtime
- DXVK-macOS
- DXMT
- vkd3d
- MoltenVK
- GStreamer, including plugins and `gst-plugin-scanner`
- FreeType
- wine-mono
- winetricks

Release builds verify Wine32-on-64 in two stages:

1. `scripts/check-wine32on64-runtime.zsh result` checks the Wine-only payload
   layout and binary file types.
2. `scripts/smoke-wine32on64-launch.zsh <assembled-runtime-root>` runs the
   runtime's 32-bit `cmd.exe` through Wine32-on-64. This smoke test requires an
   assembled runtime stack with component archives overlaid, including FreeType;
   it is not expected to pass against the Wine-only `result` artifact.

Release builds also run backend smoke probes against an assembled runtime stack.
These probes build small x86_64 Windows executables with mingw, initialize a
temporary Wine prefix, apply the same native override DLL placement expected by
Konyak, and verify DXVK D3D11, DXMT D3D11, and vkd3d D3D12 device creation.
They check runtime behavior rather than binary identity with CrossOver.

Release builds also run a GUI launch smoke against the assembled runtime stack
through `wine64 start /unix <program>`, matching Konyak's normal macOS `.exe`
launch path. The launch smoke uses the runtime `lib` directory through
`DYLD_LIBRARY_PATH` and does not rely on `DYLD_FALLBACK_LIBRARY_PATH`.

DXVK-macOS is packaged independently from GPTK/D3DMetal. The pinned Gcenx
DXVK-macOS archive provides `dxgi.dll`, `d3d9.dll`, `d3d10core.dll`, and
`d3d11.dll`; the runtime packaging supplements only `d3d10.dll` and
`d3d10_1.dll` from upstream DXVK `v1.10.3`. Release builds run
`scripts/check-dxvk-component.zsh` against the DXVK component archive and the
assembled smoke runtime so both i386 and x86_64 Windows payloads stay complete.

DXMT is packaged as a separate component and release builds run
`scripts/check-dxmt-component.zsh` against the DXMT archive. The required DXMT
payload includes both i386 and x86_64 `winemetal.dll`, `d3d11.dll`, `dxgi.dll`,
and `d3d10core.dll`, x86_64 `winemetal.so`, and the x86_64 NVIDIA shim DLLs
`nvapi64.dll` and `nvngx.dll`.

GStreamer is packaged with `libgstreamer-1.0.0.dylib`, plugin dylibs under
`lib/gstreamer-1.0`, and `libexec/gstreamer-1.0/gst-plugin-scanner`. Release
builds run `scripts/check-gstreamer-component.zsh` against the component
archive and the assembled smoke runtime, rejecting missing representative media
plugins or unpackaged `/nix/store/*.dylib` references.

vkd3d is built from the pinned CrossOver FOSS source archive as a separate
component. Release builds reuse the already-built Wine runtime artifact for
`widl`, build both i386 and x86_64 Windows DLLs, and package
`libvkd3d-1.dll`, `libvkd3d-shader-1.dll`, and `libvkd3d-utils-1.dll` into
Wine's standard `lib/wine/{i386,x86_64}-windows` directories. The parent
Konyak repository must consume this component archive instead of adding vkd3d
dependencies to its own Nix flake.

Apple GPTK/D3DMetal remains a user-imported optional layer and is not included
in this runtime repository.

The x86_64 Wine runtime is built with the CrossOver GPTK/D3DMetal loader hook
and advertises `"supportsExternalGptkD3DMetal": true` in `build-info.json`.
The aarch64 Wine build does not expose that hook because CrossOver's GPTK
loader path is x86_64/Rosetta-specific. The expected user-imported payload
layout and launch environment are documented in
`docs/gptk-d3dmetal-import-contract.md`.

To import Apple GPTK/D3DMetal into a writable runtime copy:

```sh
scripts/import-gptk-d3dmetal-redist.zsh \
  /path/to/Game_Porting_Toolkit_3.0.dmg \
  /path/to/konyak-macos-wine-runtime
```

The import script installs the nested GPTK `redist` payload into the isolated
`components/gptk-d3dmetal` runtime component and preserves the required
D3DMetal symlinks without overwriting Wine's standard `lib/wine/*` payload. It
also accepts CrossOver.app's
`Contents/SharedSupport/CrossOver/lib64/apple_gptk` payload, imports the
NVIDIA shim files `nvapi64` and `nvngx`, and normalizes older
`nvngx-on-metalfx` source names to the canonical `nvngx` runtime layout.
