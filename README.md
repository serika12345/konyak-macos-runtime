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
nix build .#konyak-macos-wine-runtime -L
```

GitHub Actions runs the same build on GitHub-hosted arm64 macOS and builds the
`aarch64-darwin` package explicitly.

## Release Contract

Runtime archives must include:

- `Licenses/`
- `SOURCE.txt`
- `build-info.json`
- a Konyak-compatible runtime stack source manifest

Apple GPTK/D3DMetal remains a user-imported optional layer and is not included
in this runtime repository.
