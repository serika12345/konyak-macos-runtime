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
  pkg-config,
  python3,
  SDL2,
  llvmPackages,
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
    llvmPackages.lld
    llvmPackages.llvm
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
