{
  lib,
  stdenv,
  fetchgit,
  git,
  meson,
  ninja,
  pkg-config,
  xxd,
  sqlite,
  zlib,
  ncurses,
  libxml2,
  pkgsCross,
  dxmtSource,
  llvm15,
  metalToolchainBin ? null,
  wineRuntime,
}:

stdenv.mkDerivation {
  pname = "konyak-macos-dxmt";
  version = "${dxmtSource.version}-konyak.0";
  __noChroot = true;

  src = fetchgit {
    url = dxmtSource.url;
    rev = dxmtSource.rev;
    hash = dxmtSource.hash;
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    git
    meson
    ninja
    pkg-config
    xxd
    pkgsCross.mingwW64.buildPackages.gcc
    pkgsCross.mingwW64.buildPackages.binutils
  ];

  buildInputs = [
    libxml2
    ncurses
    sqlite
    zlib
  ];

  dontUseMesonConfigure = true;

  configurePhase = ''
    runHook preConfigure

    export PATH="$PATH:/usr/bin"
    ${lib.optionalString (metalToolchainBin != null) ''
      mkdir -p "$TMPDIR/konyak-xcode-bin"
      cat > "$TMPDIR/konyak-xcode-bin/xcrun" <<'EOF'
#!/bin/sh
if [ "$1" = "-sdk" ] && [ "$2" = "macosx" ]; then
  shift 2
  tool="$1"
  shift
  case "$tool" in
    metal|metallib)
      exec "${metalToolchainBin}/$tool" "$@"
      ;;
  esac
fi
exec /usr/bin/xcrun "$@"
EOF
      chmod +x "$TMPDIR/konyak-xcode-bin/xcrun"
      export PATH="$TMPDIR/konyak-xcode-bin:$PATH"
    ''}
    mkdir -p "$TMPDIR/konyak-curses-lib"
    ln -sf ${ncurses}/lib/libncurses.dylib "$TMPDIR/konyak-curses-lib/libcurses.dylib"

    export NIX_LDFLAGS="$NIX_LDFLAGS -L${zlib}/lib -L$TMPDIR/konyak-curses-lib -L${ncurses}/lib -L${libxml2.out}/lib -L${sqlite.out}/lib"
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -I${sqlite.dev}/include"

    mkdir -p "$TMPDIR/konyak-wine-objects"
    (
      cd "$TMPDIR/konyak-wine-objects"
      x86_64-w64-mingw32-ar x ${wineRuntime}/lib/wine/x86_64-windows/libwinecrt0.a unix_lib.o
    )
    substituteInPlace src/winemetal/meson.build \
      --replace-fail 'winemetal_ld_args = []' \
        "winemetal_ld_args = ['$TMPDIR/konyak-wine-objects/unix_lib.o']"

    meson setup \
      --cross-file build-win64.txt \
      --buildtype=release \
      --prefix="$out" \
      -Dnative_llvm_path=${llvm15} \
      -Dwine_install_path=${wineRuntime} \
      -Dwine_builtin_dll=false \
      -Denable_tests=false \
      -Denable_nvapi=false \
      -Denable_nvngx=false \
      build .

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build --destdir "$TMPDIR/dxmt-install"

    mkdir -p "$out/x86_64-windows" "$out/x86_64-unix" "$out/Licenses"

    find "$TMPDIR/dxmt-install" -type f -name '*.dll' -print -exec cp -f {} "$out/x86_64-windows/" \;
    find "$TMPDIR/dxmt-install" -type f -name 'winemetal.so' -print -exec cp -f {} "$out/x86_64-unix/" \;

    copy_dxmt_dylib_closure() {
      local source_path="$1"
      local dependency
      local dependency_file_name
      local target_path

      dependency_file_name="$(basename "$source_path")"
      target_path="$out/x86_64-unix/$dependency_file_name"

      if [ ! -f "$source_path" ]; then
        echo "DXMT dylib dependency not found: $source_path" >&2
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

          copy_dxmt_dylib_closure "$dependency"
          dependency_file_name="$(basename "$dependency")"
          install_name_tool \
            -change "$dependency" "@loader_path/$dependency_file_name" \
            "$target_path"
        done
    }

    rewrite_dxmt_nix_dylib_references() {
      local target_path="$1"
      local dependency
      local dependency_file_name

      chmod u+w "$target_path"
      otool -L "$target_path" |
        awk 'NR > 1 { print $1 }' |
        while IFS= read -r dependency; do
          case "$dependency" in
            /nix/store/*.dylib) ;;
            *) continue ;;
          esac

          copy_dxmt_dylib_closure "$dependency"
          dependency_file_name="$(basename "$dependency")"
          install_name_tool \
            -change "$dependency" "@loader_path/$dependency_file_name" \
            "$target_path"
        done
    }

    find_dxmt_macho_nix_dylib_references() {
      local candidate_path
      local file_output

      find "$out/x86_64-unix" -type f -print |
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

    rewrite_dxmt_nix_dylib_references "$out/x86_64-unix/winemetal.so"

    remaining_nix_dylib_references="$(find_dxmt_macho_nix_dylib_references)"
    if [ -n "$remaining_nix_dylib_references" ]; then
      echo "DXMT Mach-O files still reference unpackaged Nix store dylibs:" >&2
      echo "$remaining_nix_dylib_references" >&2
      exit 1
    fi

    cp LICENSE "$out/Licenses/DXMT-LGPL-2.1-or-later.txt"
    cp COPYING.LIB "$out/Licenses/LGPL-2.1.txt"

    cat >"$out/SOURCE.txt" <<EOF
Component: Konyak macOS DXMT runtime component
Derived from: DXMT
DXMT source URL: ${dxmtSource.url}
DXMT source revision: ${dxmtSource.rev}
DXMT source hash: ${dxmtSource.hash}
Build recipe: Nix flake in serika12345/konyak-macos-runtime
Wine runtime used for build: ${wineRuntime}
EOF

    cat >"$out/build-info.json" <<EOF
{
  "schemaVersion": 1,
  "componentId": "dxmt",
  "version": "$version",
  "source": {
    "name": "dxmt",
    "url": "${dxmtSource.url}",
    "rev": "${dxmtSource.rev}",
    "hash": "${dxmtSource.hash}"
  },
  "wineRuntime": "${wineRuntime}",
  "wineBuiltinDll": false,
  "architectures": ["x86_64"]
}
EOF

    for required in \
      "$out/x86_64-windows/winemetal.dll" \
      "$out/x86_64-windows/d3d11.dll" \
      "$out/x86_64-windows/dxgi.dll" \
      "$out/x86_64-windows/d3d10core.dll" \
      "$out/x86_64-unix/winemetal.so"
    do
      if [ ! -f "$required" ]; then
        echo "Missing DXMT output: $required" >&2
        find "$out" -maxdepth 3 -type f -print >&2
        exit 1
      fi
    done

    runHook postInstall
  '';

  meta = {
    description = "Konyak macOS DXMT runtime component built from DXMT sources";
    homepage = "https://github.com/3Shain/dxmt";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.darwin;
  };
}
