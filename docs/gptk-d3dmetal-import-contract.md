# GPTK/D3DMetal Import Contract

Konyak does not distribute Apple GPTK/D3DMetal binaries from this repository.
The x86_64 Wine runtime built here must support a user-imported GPTK/D3DMetal
payload. Apple GPTK/D3DMetal is x86_64/Rosetta-oriented in CrossOver; the
aarch64 Wine build must not advertise external GPTK support.

The runtime build verifies that `lib/wine/x86_64-unix/ntdll.so` contains the
CrossOver loader hook for `CX_APPLEGPTK_LIBD3DSHARED_PATH`. Without that hook,
importing the payload below is not sufficient.

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
WINEDLLOVERRIDES=dxgi,d3d11,d3d12,nvapi64,nvngx=n,b
D3DM_SUPPORT_DXR=1
```
