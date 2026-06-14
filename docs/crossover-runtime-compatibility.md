# CrossOver Runtime Compatibility Plan

This document records the current compatibility direction for Konyak's macOS
runtime. It is intentionally more specific than the product roadmap because the
next runtime fixes must preserve normal Wine compatibility while keeping the
CrossOver-derived graphics stack.

## Goal

Konyak's macOS runtime goal is not to copy CrossOver wholesale. The goal is:

- use a CrossOver-derived Wine where needed for D3DMetal/GPTK and Wine32-on-64;
- provide DXVK, DXMT, vkd3d, MoltenVK, GStreamer, wine-mono, and wine-gecko at
  Konyak runtime quality;
- avoid breaking applications that worked with a normal upstream Wine runtime;
- keep runtime behavior reproducible from Konyak-owned artifacts instead of host
  shell state or local Homebrew/Nix paths.

## Baselines

### CrossOver.app 26.1

The installed CrossOver.app layout uses a shared library root under its
CrossOver support directory. Wine Unix modules can find common libraries such as
GnuTLS from that shared root, and the Apple GPTK payload is kept under
CrossOver's GPTK-specific library tree.

Konyak should compare against CrossOver.app for loader behavior and D3DMetal
hook expectations, but Konyak should keep its own runtime metadata, source
manifest, and user-import policy.

### nixpkgs Darwin Wine

nixpkgs Darwin Wine is the compatibility baseline for upstream-style Wine
feature coverage. It is useful for deciding which feature probes and
dependencies should be present on Darwin. It is not the D3DMetal baseline.

## Current Diagnosis

The current Konyak CrossOver-derived runtime has the right high-level direction:

- CrossOver-derived Wine is the macOS Wine source.
- Wine32-on-64 is built with `--enable-archs=i386,x86_64`.
- Vulkan is enabled.
- DXVK, DXMT, vkd3d, MoltenVK, GStreamer, FreeType, wine-mono, wine-gecko, and
  winetricks are built or packaged as explicit runtime stack payloads.
- GPTK/D3DMetal remains user-imported instead of redistributed.

The current problems are lower-level compatibility and packaging issues:

- The Wine configure flags are too hand-pruned. `--enable-archs=i386,x86_64`,
  `--with-vulkan`, and `--without-x` are intentional, but every other
  `--without-*` should be rechecked against nixpkgs Darwin Wine, CrossOver 26.1,
  and observed source-level constraints.
- `--with-gnutls` is present, but that only proves Wine was built with GnuTLS
  support. It does not prove runtime modules can resolve `libgnutls.30.dylib`.
- Unix-side Wine modules such as `secur32.so` and `bcrypt.so` use runtime
  loading paths that are not fully represented by `otool -L` checks. A package
  can pass direct dependency checks while still failing at dlopen time.
- CI smoke tests must not use search paths that the app does not set. A smoke
  test that succeeds only because of `DYLD_FALLBACK_LIBRARY_PATH` can hide a
  broken public runtime.

The Ardour splash-screen stall is consistent with this class of issue:
Schannel/GnuTLS support exists at build time but fails to initialize because
`libgnutls.30.dylib` is not available from the runtime layout seen by Wine.

## Decisions

### Public Distribution

The public default macOS runtime should be a single assembled runtime stack
archive. This reduces mismatch between "Wine archive plus components" and the
actual runtime the app expects.

CI may still produce separate internal artifacts for:

- Wine;
- DXMT;
- vkd3d;
- DXVK-macOS;
- MoltenVK;
- GStreamer;
- FreeType;
- wine-mono;
- wine-gecko;
- winetricks.

Those internal artifacts are build and verification units. They are not the
preferred public install shape for the default runtime.

### Runtime Library Root

Common Unix-side runtime dylibs should be visible from the assembled runtime's
shared library root:

```text
<runtime>/lib/libgnutls.30.dylib
<runtime>/lib/<gnutls dependency dylibs>
<runtime>/lib/libfreetype.6.dylib
<runtime>/lib/libMoltenVK.dylib
<runtime>/lib/libgstreamer-1.0.0.dylib
<runtime>/lib/gstreamer-1.0/<plugin dylibs>
```

The exact set must be generated from the packaged dependency closure, not from a
handwritten partial list.

Wine Unix modules must be able to resolve these libraries from the runtime
layout without relying on host Homebrew/Nix paths or smoke-only environment
variables. Mach-O install names and runtime checks should reflect this.

### Backends

Shared runtime library condensation is adopted, but bottle-overwrite backend
selection is not adopted.

Konyak keeps backend selection runtime-owned and reversible:

- DXVK and DXMT remain selected through backend-specific DLL paths.
- vkd3d remains a Konyak runtime stack payload.
- Backends should not overwrite bottle `system32` or `syswow64` files as the
  normal selection mechanism.
- D3DMetal/GPTK remains user-imported and isolated under
  `components/gptk-d3dmetal`.

### GPTK/D3DMetal

Konyak must not publish Apple GPTK/D3DMetal binaries. User-imported GPTK stays
separate from the base Wine payload and must survive base runtime reinstall or
update operations.

CrossOver.app may overlay GPTK files into the Wine library root, but Konyak does
not adopt that layout for redistributable artifacts.

### Normal Program Launch

The normal `.exe` launch path should still be compared against CrossOver's
wrapper behavior after the runtime library layout is repaired.

## GnuTLS Resolution Requirement

The GnuTLS problem is not solved merely by passing `--with-gnutls`.

The runtime must satisfy all of the following:

- `libgnutls.30.dylib` is present in the assembled runtime shared library root.
- Its non-system dependency closure is present in the same runtime library area
  or another declared loader-visible runtime path.
- `secur32.so`, `bcrypt.so`, and any other GnuTLS dlopen users can load it from
  a launch environment equivalent to the app's normal launch plan.
- CI checks prove this without `DYLD_FALLBACK_LIBRARY_PATH` or a host
  dependency path.

This is the concrete compatibility bar for Schannel/GnuTLS-sensitive
applications such as Ardour.

## Implementation Order

### Phase 1: Configure Flags

Recheck `runtime/konyak-macos-runtime/nix/wine-crossover.nix` configure flags.

Keep:

- `--enable-archs=i386,x86_64`;
- `--with-vulkan`;
- `--without-x`;
- `--disable-tests`.

Review every other `--without-*`. Remove it unless it is justified by a Darwin
limitation, a redistributability constraint, or a demonstrated source-level
problem.

The adopted compatibility flags are:

```text
--with-coreaudio
--with-cups
--with-ffmpeg
--with-freetype
--with-gettext
--with-gnutls
--with-gssapi
--with-gstreamer
--with-inotify
--with-krb5
--with-mingw
--with-opencl
--with-pcap
--with-pthread
--with-sdl
--with-unwind
--with-usb
--with-vulkan
```

The runtime submodule has a configure flag check so this set cannot silently
regress back to hard-pruned `--without-*` flags.

Phase 1 verification completed with a full x86_64-darwin build of
`konyak-macos-wine-runtime`. The build exposed one concrete packaging detail:
`libinotify-kqueue` was detected by configure, but its include and library paths
had to be propagated explicitly through `CPPFLAGS`, `LDFLAGS`,
`NIX_CFLAGS_COMPILE`, and `NIX_LDFLAGS` for Unix-side modules such as
`winebus.sys` to compile.

`--with-opengl` is intentionally not in this adopted Darwin set. A full
x86_64-darwin configure attempt showed that Wine 11 treats an explicit
`--with-opengl` as a hard requirement for EGL development files. nixpkgs Darwin
Wine likewise does not add OpenGL support dependencies on Darwin. Konyak should
not force that flag unless an EGL-capable Darwin packaging path is deliberately
introduced and verified.

The comparison set is:

- nixpkgs Darwin `wineWow64Packages.stable` and related full variants;
- CrossOver 26.1 source and installed runtime layout.

### Phase 2: Dependencies, dylib Layout, and Single Archive

Add the dependencies needed by the enabled probes.

Fix runtime packaging so common dylibs and closure libraries are placed where
Wine Unix modules can resolve them from the assembled runtime. Extend checks to
cover:

- direct Mach-O Nix store dylib references;
- `LC_RPATH` and install-name expectations;
- dlopen-facing dylibs such as `libgnutls.30.dylib`;
- GStreamer core, plugin directory, and scanner;
- the final single assembled archive, not only per-component artifacts.

The public source manifest should point at the single assembled archive for the
default macOS runtime. Component archives may remain workflow artifacts and
internal verification inputs.

Phase 2 is implemented for the current CrossOver-derived runtime:

- Wine packaging now places dlopen-facing libraries such as GnuTLS,
  GSSAPI/Kerberos, OpenCL, and libusb under the runtime shared library root.
- Wine binaries, Unix modules, and copied dylib closures have local Mach-O
  install names and `LC_RPATH` entries instead of Nix store loader paths.
- GStreamer and DXMT component packaging also strips Nix store `LC_RPATH`
  entries from copied Mach-O payloads and keeps local `@loader_path` lookup.
- Runtime checks validate direct Nix store dylib references and Nix store
  `LC_RPATH` entries, including the final assembled stack root.
- The release source manifest can keep individual component IDs and versions
  while pointing every component record at one verified stack archive.

Local Actions-equivalent rebuild verification completed for the Wine runtime,
DXMT, vkd3d, binary components, the assembled stack archive, and the generated
single-archive source manifest.

### Phase 3: Launch, Smoke, and Sync Behavior

After the runtime layout is fixed, verify normal `.exe` launch behavior using a
real GUI executable path, not only backend probes or prefix initialization.

Phase 3 is implemented for the current CrossOver-derived runtime:

- The parent Konyak CLI still launches macOS programs through
  `wine64 start /unix <program>`.
- A Win32 GUI probe now exercises that same launch shape from the assembled
  stack. It creates a visible window, writes a sentinel file inside the prefix,
  and fails with diagnostics if prefix initialization, `start /unix`, or
  sentinel creation does not complete before the timeout.
- Runtime smoke scripts no longer set `DYLD_FALLBACK_LIBRARY_PATH`. They use
  the app-equivalent `DYLD_LIBRARY_PATH` rooted at the assembled runtime's
  `lib` directory.
- `msync` and `esync` are mutually exclusive in the parent launch environment:
  `msync` sets `WINEMSYNC=1`, and `esync` sets `WINEESYNC=1`.
- The runtime workflow runs GUI launch smoke as a downstream job that downloads
  the assembled stack artifact. It does not depend on the CrossOver Wine
  derivation in a way that can rebuild Wine during a smoke rerun.

The single assembled stack also preserves the mixed libiconv ABI requirements
introduced by the combined Wine and component closure:

- Darwin ABI libiconv remains at the standard
  `<runtime>/lib/libiconv.2.dylib` name because `DYLD_LIBRARY_PATH` can cause
  runtime-root libraries to override macOS system libraries such as
  `/usr/lib/libiconv.2.dylib`.
- GNU libiconv is kept as `<runtime>/lib/libiconv-gnu.2.dylib` for GnuTLS and
  libraries such as `libidn2` that require `_libiconv`.
- Darwin ABI libiconv is also kept as
  `<runtime>/lib/libiconv-darwin.2.dylib` for explicit root-local retargeting.
- Immediate root `bin/*` and `lib/*` Mach-O files that declare the Darwin
  compatibility-version-7 `libiconv.2.dylib` dependency are retargeted to the
  Darwin alias after component extraction.

Local Actions-equivalent verification completed for the assembled stack layout,
direct `libgnutls.30.dylib` loading, `wine64 start /unix` GUI launch,
Wine32-on-64 launch, and the DXVK, DXMT, and vkd3d backend smoke probes.

## Non-goals

- Do not adopt bottle overwrites as Konyak's normal backend selection model.
- Do not merge user-imported GPTK/D3DMetal payloads into the base Wine archive.
- Do not weaken tests, lints, or runtime checks to pass packaging smoke.
- Do not treat a successful `wine64 --version` as proof that dlopen-facing
  runtime libraries are correctly packaged.
