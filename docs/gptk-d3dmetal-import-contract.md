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

The `redist` payload must be overlaid onto the runtime root while preserving
symlinks. The required runtime paths are:

```text
lib/external/D3DMetal.framework
lib/external/libd3dshared.dylib
lib/wine/x86_64-windows/atidxx64.dll
lib/wine/x86_64-windows/d3d11.dll
lib/wine/x86_64-windows/d3d12.dll
lib/wine/x86_64-windows/dxgi.dll
lib/wine/x86_64-windows/nvapi64.dll
lib/wine/x86_64-windows/nvngx.dll
lib/wine/x86_64-unix/atidxx64.so
lib/wine/x86_64-unix/d3d11.so
lib/wine/x86_64-unix/d3d12.so
lib/wine/x86_64-unix/dxgi.so
lib/wine/x86_64-unix/nvapi64.so
lib/wine/x86_64-unix/nvngx.so
```

These Unix library paths must remain symlinks:

```text
lib/wine/x86_64-unix/d3d11.so -> ../../external/libd3dshared.dylib
lib/wine/x86_64-unix/d3d12.so -> ../../external/libd3dshared.dylib
lib/wine/x86_64-unix/dxgi.so -> ../../external/libd3dshared.dylib
```

Do not copy those symlinks as independent Mach-O files. The D3DMetal path was
validated only when the Apple symlink structure was preserved in Wine's
standard `lib/wine/x86_64-unix` search location.

CrossOver 26.1 names the NVIDIA NGX shim `nvngx.dll` / `nvngx.so`. Konyak uses
that name as the canonical runtime layout. Import tools may accept older
`nvngx-on-metalfx` inputs as source files, but must normalize them to
`nvngx.dll` / `nvngx.so` in the installed runtime.

## Launch Contract

Konyak must set the runtime environment when GPTK/D3DMetal is selected:

```text
CX_APPLEGPTK_LIBD3DSHARED_PATH=<runtime>/lib/external/libd3dshared.dylib
DYLD_FRAMEWORK_PATH=<runtime>/lib/external
DYLD_LIBRARY_PATH=<runtime>/lib/external:<runtime>/lib/wine/x86_64-unix:<runtime library paths>
WINEDLLOVERRIDES=dxgi,d3d11,d3d12,nvapi64,nvngx=n,b
D3DM_SUPPORT_DXR=1
```

`WINEDLLPATH` is not required for the overlay layout because the Apple PE DLLs
are installed in Wine's standard `lib/wine/x86_64-windows` directory.
