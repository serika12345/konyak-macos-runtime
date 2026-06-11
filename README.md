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

The release manifest is assembled from separately published component archives:

- CrossOver-derived Wine runtime
- DXVK-macOS
- DXMT
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

DXVK-macOS is packaged independently from GPTK/D3DMetal. The pinned Gcenx
DXVK-macOS archive provides `dxgi.dll`, `d3d9.dll`, `d3d10core.dll`, and
`d3d11.dll`; the runtime packaging supplements only `d3d10.dll` and
`d3d10_1.dll` from upstream DXVK `v1.10.3`. Release builds run
`scripts/check-dxvk-component.zsh` against the DXVK component archive and the
assembled smoke runtime so both i386 and x86_64 Windows payloads stay complete.

GStreamer is packaged with `libgstreamer-1.0.0.dylib`, plugin dylibs under
`lib/gstreamer-1.0`, and `libexec/gstreamer-1.0/gst-plugin-scanner`. Release
builds run `scripts/check-gstreamer-component.zsh` against the component
archive and the assembled smoke runtime, rejecting missing representative media
plugins or unpackaged `/nix/store/*.dylib` references.

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

The import script overlays the nested GPTK `redist` payload into Wine's
standard `lib/external` and `lib/wine/x86_64-*` locations and preserves the
required D3DMetal symlinks. It also accepts CrossOver.app's
`Contents/SharedSupport/CrossOver/lib64/apple_gptk` payload, imports the
NVIDIA shim files `nvapi64` and `nvngx`, and normalizes older
`nvngx-on-metalfx` source names to the canonical `nvngx` runtime layout.
