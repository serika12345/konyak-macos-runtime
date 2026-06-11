{
  lib,
  stdenv,
  fetchurl,
  autoreconfHook,
  bison,
  flex,
  perlPackages,
  pkg-config,
  pkgsCross,
  spirv-headers,
  vulkan-headers,
  crossoverSource,
  wineRuntime,
}:

let
  version = "crossover-${crossoverSource.version}-vkd3d-1.18-konyak.0";
  src = fetchurl {
    url = crossoverSource.url;
    hash = crossoverSource.hash;
  };

  buildFor =
    { crossPkgs, windowsArch }:
    crossPkgs.stdenv.mkDerivation {
      pname = "konyak-macos-vkd3d-${windowsArch}";
      inherit version src;
      __noChroot = true;

      sourceRoot = "sources/vkd3d";

      nativeBuildInputs = [
        autoreconfHook
        bison
        flex
        perlPackages.perl
        perlPackages.JSON
        pkg-config
      ];

      buildInputs = [
        spirv-headers
        vulkan-headers
      ];

      configureFlags = [
        "--disable-doxygen-doc"
        "--disable-demos"
        "--disable-tests"
        "--without-ncurses"
        "--without-opengl"
        "--without-spirv-tools"
        "--without-xcb"
      ];

      preConfigure = ''
                mkdir -p "$TMPDIR/konyak-widl-bin"
                cat > "$TMPDIR/konyak-widl-bin/widl" <<'EOF'
        #!/bin/sh
        if [ "''${1:-}" = "-V" ]; then
          echo "Wine IDL Compiler version 11.0"
          exit 0
        fi
        exec "__KONYAK_WIDL__" "$@"
        EOF
                substituteInPlace "$TMPDIR/konyak-widl-bin/widl" \
                  --replace-fail "__KONYAK_WIDL__" "${wineRuntime}/bin/widl"
                chmod +x "$TMPDIR/konyak-widl-bin/widl"

                export WIDL="$TMPDIR/konyak-widl-bin/widl"
                export SONAME_LIBVULKAN="vulkan-1.dll"
                export CPPFLAGS="$CPPFLAGS -I${vulkan-headers}/include -I${spirv-headers}/include -DVKD3D_ABORT_ON_ERR"
                export CFLAGS="$CFLAGS -O2 -Wno-array-bounds"
                export LDFLAGS="$LDFLAGS -static-libgcc"
      '';

      enableParallelBuilding = true;
    };

  vkd3d64 = buildFor {
    crossPkgs = pkgsCross.mingwW64;
    windowsArch = "x86_64";
  };
  vkd3d32 = buildFor {
    crossPkgs = pkgsCross.mingw32;
    windowsArch = "i386";
  };
in
stdenv.mkDerivation {
  pname = "konyak-macos-vkd3d";
  inherit version;

  dontUnpack = true;

  installPhase = ''
        runHook preInstall

        mkdir -p "$out/x86_64-windows" "$out/i386-windows" "$out/Licenses"

        for dll_name in libvkd3d-1.dll libvkd3d-shader-1.dll libvkd3d-utils-1.dll; do
          cp -f "${vkd3d64}/bin/$dll_name" "$out/x86_64-windows/$dll_name"
          cp -f "${vkd3d32}/bin/$dll_name" "$out/i386-windows/$dll_name"
        done

        tar -xOf "${src}" sources/vkd3d/COPYING > "$out/Licenses/VKD3D-COPYING.txt"
        tar -xOf "${src}" sources/vkd3d/LICENSE > "$out/Licenses/VKD3D-LGPL-2.1.txt"

        cat >"$out/SOURCE.txt" <<EOF
    Component: Konyak macOS vkd3d runtime component
    Derived from: CrossOver FOSS vkd3d source
    CrossOver source URL: ${crossoverSource.url}
    CrossOver source hash: ${crossoverSource.hash}
    Build recipe: Nix flake in serika12345/konyak-macos-runtime
    Wine runtime used for build: ${wineRuntime}
    EOF

        cat >"$out/build-info.json" <<EOF
    {
      "schemaVersion": 1,
      "componentId": "vkd3d",
      "version": "$version",
      "source": {
        "name": "crossover-vkd3d",
        "url": "${crossoverSource.url}",
        "hash": "${crossoverSource.hash}",
        "vkd3dVersion": "1.18"
      },
      "wineRuntime": "${wineRuntime}",
      "architectures": ["i386", "x86_64"]
    }
    EOF

        for required in \
          "$out/x86_64-windows/libvkd3d-1.dll" \
          "$out/x86_64-windows/libvkd3d-shader-1.dll" \
          "$out/x86_64-windows/libvkd3d-utils-1.dll" \
          "$out/i386-windows/libvkd3d-1.dll" \
          "$out/i386-windows/libvkd3d-shader-1.dll" \
          "$out/i386-windows/libvkd3d-utils-1.dll"
        do
          if [ ! -f "$required" ]; then
            echo "Missing vkd3d output: $required" >&2
            find "$out" -maxdepth 3 -type f -print >&2
            exit 1
          fi
        done

        runHook postInstall
  '';

  meta = {
    description = "Konyak macOS vkd3d runtime component built from CrossOver sources";
    homepage = "https://gitlab.winehq.org/wine/vkd3d";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.darwin;
  };
}
