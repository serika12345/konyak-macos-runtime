{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  freetype,
  gettext,
  gst_all_1,
  gnutls,
  libpcap,
  libjpeg,
  libpng,
  libtiff,
  moltenvk,
  perl,
  pkg-config,
  python3,
  SDL2,
  llvmPackages,
  xz,
  zlib,
  zstd,
  crossoverSource,
}:

let
  supportsExternalGptkD3DMetal = stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64;
  wineUnixArch = "${stdenv.hostPlatform.parsed.cpu.name}-unix";
  wine32On64RequiredPaths = [
    "lib/wine/i386-windows/ntdll.dll"
    "lib/wine/x86_64-windows/wow64.dll"
    "lib/wine/x86_64-windows/wow64cpu.dll"
    "lib/wine/x86_64-windows/wow64win.dll"
    "lib/wine/${wineUnixArch}/ntdll.so"
  ];
in
stdenv.mkDerivation {
  pname = "konyak-macos-wine-runtime";
  version = "crossover-${crossoverSource.version}-konyak.0";

  src = fetchurl {
    url = crossoverSource.url;
    hash = crossoverSource.hash;
  };

  sourceRoot = "sources/wine";

  nativeBuildInputs = [
    bison
    flex
    llvmPackages.lld
    llvmPackages.llvm
    perl
    pkg-config
    python3
    xz
    zstd
  ];

  buildInputs = [
    gettext
    freetype
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gnutls
    libpcap
    libjpeg
    libpng
    libtiff
    moltenvk
    SDL2
    zlib
  ];

  configureFlags = [
    "--prefix=${placeholder "out"}"
    "--enable-archs=i386,x86_64"
    "--disable-tests"
    "--disable-win16"
    "--without-alsa"
    "--without-capi"
    "--without-dbus"
    "--without-gphoto"
    "--without-inotify"
    "--without-krb5"
    "--without-oss"
    "--without-pulse"
    "--without-sane"
    "--without-udev"
    "--without-unwind"
    "--without-usb"
    "--without-x"
    "--with-freetype"
    "--with-gnutls"
    "--with-gstreamer"
    "--with-pcap"
    "--with-sdl"
    "--with-vulkan"
  ];

  enableParallelBuilding = true;

  preConfigure = ''
    export MACOSX_DEPLOYMENT_TARGET=14.0

    # DXMT's upstream cross file links with mingw ld.bfd. Wine's PE static
    # libraries default to lld-link /lib archives, which expose symbols to nm
    # but are not pulled correctly by ld.bfd. Build those static libraries with
    # ar so the exported runtime can be consumed by DXMT without a custom linker.
    substituteInPlace tools/winebuild/import.c \
      --replace-fail 'if (!create || target.platform != PLATFORM_WINDOWS)' 'if (1)' \
      --replace-fail 'strarray_add( &args, create ? "rc" : "r" );' 'strarray_add( &args, create ? "rcs" : "rs" );'

    # CrossOver's macOS D3DMetal layer is x86_64-only. The Konyak runtime is
    # built on arm64-darwin too, so keep the Wine mac driver buildable there.
    substituteInPlace dlls/winemac.drv/cocoa_window.m \
      --replace-fail '        CAMetalLayer *layer = [WineMetalLayer layer];   /* CW HACK 22435 */' \
        '        CAMetalLayer *layer;
#if defined(__x86_64__)
        layer = [WineMetalLayer layer];   /* CW HACK 22435 */
#else
        layer = [CAMetalLayer layer];
#endif'

    perl -0pi -e 's/\n#endif\n\z/\n#else\n\n#include "config.h"\n#include "macdrv.h"\n\nvoid macdrv_client_surface_presented(const macdrv_event *event)\n{\n}\n\n#endif\n/' \
      dlls/winemac.drv/d3dmetal.c

    # Konyak distributes FreeType as a runtime stack component overlaid into
    # $runtime/lib. Wine's macOS loader re-execs through a temporary binary, so
    # DYLD_* search paths and @loader_path in dlopen strings are not reliable
    # for FreeType's late dlopen calls. Resolve FreeType from the Unix-side Wine
    # DLL path reported by dladdr instead.
    substituteInPlace dlls/win32u/freetype.c dlls/dwrite/freetype.c \
      --replace-fail 'dlopen(SONAME_LIBFREETYPE, RTLD_NOW)' \
        'konyak_dlopen_runtime_freetype()'
    substituteInPlace dlls/dwrite/freetype.c \
      --replace-fail '#include <dlfcn.h>' '#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>'
    substituteInPlace dlls/win32u/freetype.c dlls/dwrite/freetype.c \
      --replace-fail 'static void *ft_handle = NULL;' 'static void *ft_handle = NULL;

#ifdef __APPLE__
static void *konyak_dlopen_freetype_path(const char *path)
{
    void *handle;

    if (!path || !path[0]) return NULL;
    handle = dlopen(path, RTLD_NOW);
    if (!handle) WARN("Failed to load Konyak FreeType %s: %s\n", path, dlerror());
    return handle;
}

static void *konyak_dlopen_runtime_freetype_from_winedllpath(void)
{
    const char *cursor = getenv("WINEDLLPATH");
    char entry[4096];
    char freetype_path[4096];

    while (cursor && *cursor)
    {
        const char *end = strchr(cursor, 58);
        size_t entry_length = end ? (size_t)(end - cursor) : strlen(cursor);

        if (entry_length > 0 && entry_length < sizeof(entry))
        {
            char *marker;

            memcpy(entry, cursor, entry_length);
            entry[entry_length] = 0;
            if ((marker = strstr(entry, "/lib/wine")))
            {
                int lib_length = (int)(marker - entry + 4);
                int length = snprintf(freetype_path, sizeof(freetype_path),
                                      "%.*s/libfreetype.6.dylib", lib_length, entry);
                if (length > 0 && length < sizeof(freetype_path))
                {
                    void *handle = konyak_dlopen_freetype_path(freetype_path);
                    if (handle) return handle;
                }
            }
        }

        if (!end) break;
        cursor = end + 1;
    }

    return NULL;
}

static void *konyak_dlopen_runtime_freetype(void)
{
    Dl_info info;
    char image_path[4096];
    char freetype_path[4096];
    char *slash;
    int length;
    void *handle;

    if ((handle = konyak_dlopen_runtime_freetype_from_winedllpath())) return handle;

    if (dladdr((const void *)konyak_dlopen_runtime_freetype, &info) && info.dli_fname &&
        (length = snprintf(image_path, sizeof(image_path), "%s", info.dli_fname)) > 0 &&
        length < sizeof(image_path) && (slash = strrchr(image_path, 47)))
    {
        *slash = 0;
        length = snprintf(freetype_path, sizeof(freetype_path), "%s/../../libfreetype.6.dylib",
                          image_path);
        if (length > 0 && length < sizeof(freetype_path))
        {
            handle = dlopen(freetype_path, RTLD_NOW);
            if (handle) return handle;
            WARN("Failed to load Konyak FreeType %s: %s\n", freetype_path, dlerror());
        }
    }

    return dlopen(SONAME_LIBFREETYPE, RTLD_NOW);
}
#else
static void *konyak_dlopen_runtime_freetype(void)
{
    return dlopen(SONAME_LIBFREETYPE, RTLD_NOW);
}
#endif'

    mkdir -p "$TMPDIR/konyak-llvm-bin"
    ln -sf ${llvmPackages.clang-unwrapped}/bin/clang "$TMPDIR/konyak-llvm-bin/clang"
    ln -sf ${llvmPackages.lld}/bin/lld-link "$TMPDIR/konyak-llvm-bin/lld-link"
    ln -sf ${llvmPackages.lld}/bin/ld.lld "$TMPDIR/konyak-llvm-bin/ld.lld"
    cat > "$TMPDIR/konyak-llvm-bin/llvm-ar" <<EOF
#!/bin/sh
exec ${llvmPackages.llvm}/bin/llvm-ar --format=gnu "\$@"
EOF
    chmod +x "$TMPDIR/konyak-llvm-bin/llvm-ar"
    ln -sf ${llvmPackages.llvm}/bin/llvm-dlltool "$TMPDIR/konyak-llvm-bin/llvm-dlltool"
    ln -sf ${llvmPackages.llvm}/bin/llvm-ranlib "$TMPDIR/konyak-llvm-bin/llvm-ranlib"
    export PATH="$TMPDIR/konyak-llvm-bin:$PATH"

    export x86_64_CC=${llvmPackages.clang-unwrapped}/bin/clang
    export i386_CC=${llvmPackages.clang-unwrapped}/bin/clang
    export CROSSCFLAGS="-g -O2"
    export CROSSLDFLAGS=""

    export CPPFLAGS="$CPPFLAGS -I${libpcap}/include"
    export LDFLAGS="$LDFLAGS -L${libpcap}/lib"
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I${libpcap}/include -Wno-error=implicit-function-declaration"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${libpcap}/lib -rpath ${moltenvk}/lib ${llvmPackages.compiler-rt}/lib/darwin/libclang_rt.osx.a"
  '';

  configurePhase = ''
    runHook preConfigure
    echo "configure flags: $configureFlags"
    if ! ./configure $configureFlags; then
      if [ -f config.log ]; then
        echo "----- config.log -----"
        cat config.log
        echo "----- end config.log -----"
      fi
      exit 1
    fi
    runHook postConfigure
  '';

  postInstall = ''
    ntdll_unix="$(find "$out/lib/wine" -path '*/ntdll.so' -type f | head -n 1)"
    if [ -z "$ntdll_unix" ]; then
      echo "Missing Wine Unix ntdll under: $out/lib/wine" >&2
      exit 1
    fi

    if ${lib.boolToString supportsExternalGptkD3DMetal}; then
      for required_gptk_hook in \
        "CX_APPLEGPTK_LIBD3DSHARED_PATH" \
        "Loading libd3dshared.dylib failed" \
        "Loaded libd3dshared.dylib"
      do
        if ! strings "$ntdll_unix" | grep -F "$required_gptk_hook" >/dev/null; then
          echo "Wine Unix ntdll is missing GPTK/D3DMetal hook string: $required_gptk_hook" >&2
          exit 1
        fi
      done

      mkdir -p "$out/lib/external"
    fi

    for required_wine32on64_path in ${lib.escapeShellArgs wine32On64RequiredPaths}; do
      if [ ! -e "$out/$required_wine32on64_path" ]; then
        echo "Missing Wine32-on-64 runtime path: $required_wine32on64_path" >&2
        exit 1
      fi
    done

    if [ -e "$out/lib/wine/i386-unix/ntdll.so" ]; then
      echo "Unexpected i386 Unix Wine host path in Wine32-on-64 runtime." >&2
      exit 1
    fi

    copy_runtime_dylib_closure() {
      local source_path="$1"
      local dependency
      local dependency_file_name
      local target_path

      dependency_file_name="$(basename "$source_path")"
      target_path="$out/lib/$dependency_file_name"

      if [ ! -f "$source_path" ]; then
        echo "Runtime dylib dependency not found: $source_path" >&2
        exit 1
      fi

      if [ -f "$target_path" ]; then
        return 0
      fi

      cp -Lf "$source_path" "$target_path"
      chmod u+w "$target_path"
      install_name_tool -id "@rpath/$dependency_file_name" "$target_path"

      otool -L "$source_path" |
        awk 'NR > 1 { print $1 }' |
        while IFS= read -r dependency; do
          case "$dependency" in
            /nix/store/*.dylib) ;;
            *) continue ;;
          esac

          if [ "$dependency" = "$source_path" ]; then
            continue
          fi

          copy_runtime_dylib_closure "$dependency"
          dependency_file_name="$(basename "$dependency")"
          install_name_tool \
            -change "$dependency" "@loader_path/$dependency_file_name" \
            "$target_path"
        done
    }

    runtime_dylib_reference() {
      local target_path="$1"
      local dependency_file_name="$2"

      case "$target_path" in
        "$out/bin/"*)
          printf '@loader_path/../lib/%s\n' "$dependency_file_name"
          ;;
        "$out/lib/wine/"*)
          printf '@loader_path/../../%s\n' "$dependency_file_name"
          ;;
        "$out/lib/"*)
          printf '@loader_path/%s\n' "$dependency_file_name"
          ;;
        *)
          printf '@rpath/%s\n' "$dependency_file_name"
          ;;
      esac
    }

    rewrite_nix_dylib_references() {
      local target_path="$1"
      local dependency
      local dependency_file_name
      local replacement_reference

      chmod u+w "$target_path"
      otool -L "$target_path" |
        awk 'NR > 1 { print $1 }' |
        while IFS= read -r dependency; do
          case "$dependency" in
            /nix/store/*.dylib) ;;
            *) continue ;;
          esac

          copy_runtime_dylib_closure "$dependency"
          dependency_file_name="$(basename "$dependency")"
          replacement_reference="$(runtime_dylib_reference "$target_path" "$dependency_file_name")"
          install_name_tool \
            -change "$dependency" "$replacement_reference" \
            "$target_path"
        done
    }

    find_macho_nix_dylib_references() {
      local candidate_path
      local file_output

      find "$out/bin" "$out/lib" -type f -print |
        while IFS= read -r candidate_path; do
          file_output="$(/usr/bin/file "$candidate_path")"
          case "$file_output" in
            *Mach-O*) ;;
            *) continue ;;
          esac

          otool -L "$candidate_path" |
            awk -v relative_path="''${candidate_path#$out/}" \
              'NR > 1 && $1 ~ /^\/nix\/store\/.*\.dylib$/ { print relative_path ": " $1 }'
        done
    }

    find "$out/bin" "$out/lib" -type f -print |
      while IFS= read -r candidate_path; do
        file_output="$(/usr/bin/file "$candidate_path")"
        case "$file_output" in
          *Mach-O*) ;;
          *) continue ;;
        esac

        rewrite_nix_dylib_references "$candidate_path"
      done

    remaining_nix_dylib_references="$(find_macho_nix_dylib_references)"
    if [ -n "$remaining_nix_dylib_references" ]; then
      echo "Wine runtime Mach-O files still reference unpackaged Nix store dylibs:" >&2
      echo "$remaining_nix_dylib_references" >&2
      exit 1
    fi

    mkdir -p "$out/Licenses"
    cp COPYING.LIB "$out/Licenses/Wine-LGPL-2.1-or-later.txt"
    cat >"$out/SOURCE.txt" <<EOF
Component: Konyak macOS Wine runtime
Derived from: CodeWeavers CrossOver FOSS source archive
CrossOver source version: ${crossoverSource.version}
CrossOver source URL: ${crossoverSource.url}
CrossOver source hash: ${crossoverSource.hash}
Build recipe: Nix flake in serika12345/konyak-macos-runtime
GPTK/D3DMetal: not included
External GPTK/D3DMetal import: ${if supportsExternalGptkD3DMetal then "supported when supplied by the user" else "not supported by this architecture"}
EOF
    cat >"$out/build-info.json" <<EOF
{
  "schemaVersion": 1,
  "componentId": "wine",
  "version": "$version",
  "source": {
    "name": "crossover-sources-${crossoverSource.version}",
    "url": "${crossoverSource.url}",
    "hash": "${crossoverSource.hash}"
  },
  "containsGptkD3DMetal": false,
  "supportsWine32On64": true,
  "wine32On64": {
    "runtimeLayout": "${wineUnixArch}-host-with-i386-windows",
    "requiresI386UnixHost": false,
    "requiredPaths": [
${lib.concatMapStringsSep ",\n" (path: "      \"${path}\"") wine32On64RequiredPaths}
    ]
  },
  "supportsExternalGptkD3DMetal": ${builtins.toJSON supportsExternalGptkD3DMetal},
  "externalGptkD3DMetal": {
    "loaderEnvironmentVariable": "CX_APPLEGPTK_LIBD3DSHARED_PATH",
    "importMode": "overlay",
    "sourceRoot": "redist",
    "runtimeRoot": ".",
    "requiredPaths": [
      "lib/external/D3DMetal.framework",
      "lib/external/libd3dshared.dylib",
      "lib/wine/x86_64-windows/atidxx64.dll",
      "lib/wine/x86_64-windows/d3d11.dll",
      "lib/wine/x86_64-windows/d3d12.dll",
      "lib/wine/x86_64-windows/dxgi.dll",
      "lib/wine/x86_64-windows/nvapi64.dll",
      "lib/wine/x86_64-windows/nvngx.dll",
      "lib/wine/x86_64-unix/atidxx64.so",
      "lib/wine/x86_64-unix/d3d11.so",
      "lib/wine/x86_64-unix/d3d12.so",
      "lib/wine/x86_64-unix/dxgi.so",
      "lib/wine/x86_64-unix/nvapi64.so",
      "lib/wine/x86_64-unix/nvngx.so"
    ],
    "requiredSymlinks": [
      {
        "path": "lib/wine/x86_64-unix/d3d11.so",
        "target": "../../external/libd3dshared.dylib"
      },
      {
        "path": "lib/wine/x86_64-unix/d3d12.so",
        "target": "../../external/libd3dshared.dylib"
      },
      {
        "path": "lib/wine/x86_64-unix/dxgi.so",
        "target": "../../external/libd3dshared.dylib"
      }
    ]
  }
}
EOF
  '';

  meta = {
    description = "Konyak macOS Wine runtime built from CrossOver FOSS sources";
    homepage = "https://www.codeweavers.com/crossover/source";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.darwin;
  };
}
