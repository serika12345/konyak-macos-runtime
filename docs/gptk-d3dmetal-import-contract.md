# GPTK/D3DMetal Import Contract

Konyak does not distribute Apple GPTK/D3DMetal binaries from this repository.
The x86_64 Wine runtime built here must support a user-imported GPTK/D3DMetal
payload. Apple GPTK/D3DMetal is x86_64/Rosetta-oriented in CrossOver; the
aarch64 Wine build must not advertise external GPTK support.

The runtime build verifies that `lib/wine/x86_64-unix/ntdll.so` contains the
CrossOver loader hook for `CX_APPLEGPTK_LIBD3DSHARED_PATH`. Without that hook,
importing the payload below is not sufficient.

The x86_64 runtime also ships `lib/wine/x86_64-unix/cxcompatdb.so` as a
Konyak-owned minimal GPTK/D3DMetal loader shim. CrossOver Wine's public
`ntdll` loader opens that path during startup, and the shim uses only the
exported `add_load_order_override` and `prepend_dll_path` hooks. It derives the
GPTK Wine root from `CX_APPLEGPTK_LIBD3DSHARED_PATH`, sets
`CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`, prepends the GPTK Wine root to Wine's
internal DLL path list, and applies the native D3DMetal load order for
`dxgi,d3d11,d3d12,nvapi64,nvngx`. It is not CrossOver's proprietary
compatibility database and must not grow title-specific DB behavior, signature
checks, process/file patching, or redirect policy.

## Source Payload

Apple GPTK 3.0 ships the Windows evaluation environment as a nested DMG. The
outer `Game_Porting_Toolkit_3.0.dmg` contains:

```text
Evaluation environment for Windows games 3.0.dmg
```

The nested DMG contains the redistributable Wine-facing payload under:

```text
redist/
```

Import tools must use that `redist` directory as the source payload.

CI may also use the pinned Gcenx Game Porting Toolkit release archive as a
transient smoke input. That archive contains an application bundle layout; the
Wine-facing payload used by the CI import script is:

```text
Game Porting Toolkit.app/Contents/Resources/wine/lib
```

The Gcenx archive is not a Konyak runtime component. CI must verify the pinned
archive SHA-256, import it only into an unpacked smoke runtime under a temporary
work directory, and must not upload the archive, extracted app bundle, imported
`components/gptk-d3dmetal`, or derived D3DMetal files as workflow artifacts or
release assets. CI maintainers are responsible for complying with the Apple
D3DMetal/GPTK license terms referenced by the Gcenx release; Konyak runtime
`Licenses/` must describe only components shipped by Konyak.

GitHub hosted macOS arm64 runners expose an Apple Paravirtual GPU that
D3DMetal rejects after the GPTK loader path is reached. CI jobs may set
`KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST=1` to accept only the exact unsupported-host
signature emitted by D3DMetal on that hosted runner. D3D10 GPTK smoke must not
claim render support from bridge reachability. The expected GPTK/D3DMetal D3D10
contract is unsupported. `smoke-backend-device.zsh <runtime>
gptk-d3d10-unsupported` must route `dxgi` / `d3d11` from the isolated
GPTK/D3DMetal component, fail if the render/readback success marker appears,
forbid DXVK/DXMT or winevulkan render fallback, and require the known
unsupported `0x80004005` signature until a future reviewed change proves native
GPTK/D3DMetal D3D10 render/readback. Wine `+loaddll` may report the component
`dxgi` / `d3d11` files as either native or builtin; the maintained proof is the
resolved component path plus the unsupported HRESULT, not the display label
alone.

The actual maintained D3D10 render proof for the bundled runtime stack is the
DXVK path. `smoke-backend-device.zsh <runtime> dxvk-d3d10-render` creates a
D3D10 device, clears an offscreen render target, copies it to a staging texture,
and verifies the readback pixel. DXMT remains covered by its D3D11 backend
smoke; this runtime does not claim DXMT D3D10 render support.

Konyak also targets CrossOver-equivalent D3D10 fallback behavior. CrossOver.app
passes the D3D10 render/readback probe through builtin WineD3D with winevulkan,
not through GPTK/D3DMetal. Runtime smoke coverage must therefore add a maintained
base-Wine `wined3d-d3d10-render` path. `smoke-backend-device.zsh <runtime>
wined3d-d3d10-render` uses builtin `d3d10`, `d3d10core`, `d3d11`, `dxgi`,
`wined3d`, and `winevulkan` without DXVK, DXMT, or GPTK override paths, then
verifies the same D3D10 render/readback marker as the DXVK path.

CrossOver's bundled MoltenVK is part of the WineD3D/Vulkan D3D10 fallback
contract. The CrossOver FOSS MoltenVK source advertises D3D10-relevant Vulkan
feature bits on Apple GPUs that upstream MoltenVK release binaries do not
advertise, including `geometryShader`, `pipelineStatisticsQuery`, and
`shaderCullDistance` comments that explicitly reference DXVK/D3D10 or related
compatibility. Konyak must not patch the CrossOver Wine derivation to emulate
those feature bits inside WineD3D. Instead, the runtime owner builds a
`konyak-macos-moltenvk` component from the pinned CrossOver FOSS source and
packages that component as `konyak-macos-moltenvk.tar.zst`.

The MoltenVK recipe must fail if the pinned CrossOver source no longer contains
the expected D3D10 feature-advertisement source lines. The component archive
must contain `lib/libMoltenVK.dylib`, be universal `x86_64`/`arm64`, carry the
install name `@rpath/libMoltenVK.dylib`, avoid unpackaged Nix store dylib
references, and declare `components.moltenvk` in `.konyak-runtime-stack.json`.
The maintained behavioral proof remains the dynamic `wined3d-d3d10-render`
smoke rather than static binary inspection alone.

## Runtime Layout

The `redist` payload must be installed as an isolated optional component while
preserving symlinks. Import tools must not overwrite the base Wine payload under
`lib/wine/*`. The required runtime paths are:

```text
components/gptk-d3dmetal/lib/external/D3DMetal.framework
components/gptk-d3dmetal/lib/external/libd3dshared.dylib
components/gptk-d3dmetal/lib/wine/x86_64-windows/atidxx64.dll
components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d11.dll
components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d12.dll
components/gptk-d3dmetal/lib/wine/x86_64-windows/dxgi.dll
components/gptk-d3dmetal/lib/wine/x86_64-windows/nvapi64.dll
components/gptk-d3dmetal/lib/wine/x86_64-windows/nvngx.dll
components/gptk-d3dmetal/lib/wine/x86_64-unix/atidxx64.so
components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d11.so
components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d12.so
components/gptk-d3dmetal/lib/wine/x86_64-unix/dxgi.so
components/gptk-d3dmetal/lib/wine/x86_64-unix/nvapi64.so
components/gptk-d3dmetal/lib/wine/x86_64-unix/nvngx.so
```

These Unix library paths must remain symlinks:

```text
components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d11.so -> ../../external/libd3dshared.dylib
components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d12.so -> ../../external/libd3dshared.dylib
components/gptk-d3dmetal/lib/wine/x86_64-unix/dxgi.so -> ../../external/libd3dshared.dylib
```

Do not install Apple GPTK `d3d10.dll` or `d3d10.so` into the active
`components/gptk-d3dmetal` layout. CrossOver's shipped GPTK layout does not
override D3D10. D3D10 must be routed outside GPTK/D3DMetal: DXVK is the primary
D3D10 render path, and the base WineD3D/winevulkan route is the
CrossOver-equivalent fallback path.

Do not copy those symlinks as independent Mach-O files. The D3DMetal component
must be kept across base runtime reinstall/update operations. Legacy imports
that were previously placed under `lib/external` and `lib/wine/x86_64-*` should
be migrated into `components/gptk-d3dmetal` during reinstall.

CrossOver 26.1 names the NVIDIA NGX shim `nvngx.dll` / `nvngx.so`. Konyak uses
that name as the canonical runtime layout. Import tools may accept older
`nvngx-on-metalfx` inputs as source files, but must normalize them to
`nvngx.dll` / `nvngx.so` in the installed runtime.

## Launch Contract

Konyak must set the runtime environment when GPTK/D3DMetal is selected:

```text
CX_APPLEGPTK_LIBD3DSHARED_PATH=<runtime>/components/gptk-d3dmetal/lib/external/libd3dshared.dylib
DYLD_FRAMEWORK_PATH=<runtime>/components/gptk-d3dmetal/lib/external
DYLD_LIBRARY_PATH=<runtime>/components/gptk-d3dmetal/lib/external:<runtime>/components/gptk-d3dmetal/lib/wine/x86_64-unix:<runtime library paths>
WINEDLLPATH=<runtime>/components/gptk-d3dmetal/lib/wine/x86_64-windows:<base Wine DLL paths>
WINEPATH=Z:\path\to\runtime\components\gptk-d3dmetal\lib\wine\x86_64-windows
WINEDLLOVERRIDES=dxgi,d3d11,d3d12,nvapi64,nvngx=n,b
D3DM_SUPPORT_DXR=1
```

When Konyak launches a macOS program that imports D3D10 while GPTK/D3DMetal is
selected, the application launch contract must not leave the process on the
native GPTK/D3DMetal route. The parent CLI should select the base WineD3D /
winevulkan fallback for that run, remove stale GPTK/D3DMetal override DLLs from
the bottle, and emit machine-readable diagnostics:

```text
KONYAK_GRAPHICS_BACKEND_REQUESTED=gptk-d3dmetal
KONYAK_GRAPHICS_BACKEND_SELECTED=wined3d-vulkan
KONYAK_GRAPHICS_BACKEND_FALLBACK_REASON=gptkD3d10Unsupported
```

D3D12 imports take priority over D3D10 imports. A program that imports D3D12
must remain on GPTK/D3DMetal when GPTK/D3DMetal is selected.
