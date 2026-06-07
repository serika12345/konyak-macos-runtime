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
required D3DMetal symlinks.
