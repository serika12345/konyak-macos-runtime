{
  lib,
  stdenv,
  fetchurl,
  bison,
  flex,
  gettext,
  gnutls,
  libjpeg,
  libpng,
  libtiff,
  moltenvk,
  pkg-config,
  python3,
  SDL2,
  xz,
  zlib,
  zstd,
  crossoverSource,
}:

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
    pkg-config
    python3
    xz
    zstd
  ];

  buildInputs = [
    gettext
    gnutls
    libjpeg
    libpng
    libtiff
    moltenvk
    SDL2
    zlib
  ];

  configureFlags = [
    "--prefix=${placeholder "out"}"
    "--enable-win64"
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
    "--with-sdl"
    "--with-vulkan"
  ];

  enableParallelBuilding = true;

  preConfigure = ''
    export MACOSX_DEPLOYMENT_TARGET=11.0
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=implicit-function-declaration"
    export NIX_LDFLAGS="$NIX_LDFLAGS -rpath ${moltenvk}/lib"
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
  "containsGptkD3DMetal": false
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
