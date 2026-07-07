{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  git,
  gnumake,
  python3,
  unzip,
  crossoverSource,
}:

let
  konyakRevision = toString (crossoverSource.konyakRevision or 0);
  version = "crossover-${crossoverSource.version}-moltenvk-konyak.${konyakRevision}";
  src = fetchurl {
    url = crossoverSource.url;
    hash = crossoverSource.hash;
  };

  cerealSrc = fetchFromGitHub {
    owner = "USCiLab";
    repo = "cereal";
    rev = "51cbda5f30e56c801c07fe3d3aba5d7fb9e6cca4";
    hash = "sha256-pGeb0e3dFcS6pdhvqWyBgGCtSwOEe/S+v+W9N0BGebI=";
  };

  glslangSrc = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "glslang";
    rev = "fa9c3deb49e035a8abcabe366f26aac010f6cbfb";
    hash = "sha256-slKBFq6NyWHQmJq/YR3LmbGnHyZgRg0hej90tZDOGzA=";
  };

  spirvToolsSrc = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Tools";
    rev = "0cfe9e7219148716dfd30b37f4d21753f098707a";
    hash = "sha256-5swjNHeJpsCDkUVBL1uFqAzOPFzCESsYtDfRkno2bN4=";
  };

  spirvHeadersSrc = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "SPIRV-Headers";
    rev = "2acb319af38d43be3ea76bfabf3998e5281d8d12";
    hash = "sha256-c9ruBCnf9PNJz030bfRhHwyqju6T8YCRx+efKCEYgSo=";
  };

  vulkanHeadersSrc = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "Vulkan-Headers";
    rev = "fc6c06ac529e4b4b6e34c17cc650a8f62dee2eb0";
    hash = "sha256-IjxM6MmIEISUIPn2FguxyHGO1bhomYOz3XLjXO4/gWM=";
  };

  vulkanToolsSrc = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "Vulkan-Tools";
    rev = "b47676a03827fc0c287409b243b1fd62886e79c0";
    hash = "sha256-i0dV4Scvn/KzYmA/jgz8X7XkvKXdosgWPAW8azgqGis=";
  };

  volkSrc = fetchFromGitHub {
    owner = "zeux";
    repo = "volk";
    rev = "466085407d5d2f50583fd663c1d65f93a7709d3e";
    hash = "sha256-SbTBwS4mJETrXRT7QMJX9F8ukcZmzz8+1atVbB/fid4=";
  };
in
stdenv.mkDerivation {
  pname = "konyak-macos-moltenvk";
  inherit version src;
  __noChroot = true;

  sourceRoot = "sources/moltenvk";

  nativeBuildInputs = [
    git
    gnumake
    python3
    unzip
  ];

  dontConfigure = true;

  postPatch = ''
    for required_feature in \
      'geometryShader = true;  // XXX Required by DXVK for D3D10' \
      'pipelineStatisticsQuery = true; // XXX Required by Damavand' \
      'shaderCullDistance = true;  // XXX Required by DXVK for 10level9'
    do
      if ! grep -F "$required_feature" MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm >/dev/null; then
        echo "CrossOver MoltenVK source is missing expected D3D10 feature advertisement: $required_feature" >&2
        exit 1
      fi
    done
  '';

  buildPhase = ''
    runHook preBuild

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
      echo "Xcode xcodebuild is required to build CrossOver MoltenVK from source." >&2
      exit 1
    fi

    copy_external_source() {
      local source_path="$1"
      local target_path="$2"

      rm -rf "$target_path"
      cp -R "$source_path" "$target_path"
      chmod -R u+w "$target_path"
    }

    copy_external_source "${cerealSrc}" External/cereal
    copy_external_source "${glslangSrc}" External/glslang
    mkdir -p External/glslang/External
    copy_external_source "${spirvToolsSrc}" External/glslang/External/spirv-tools
    mkdir -p External/glslang/External/spirv-tools/external
    copy_external_source "${spirvHeadersSrc}" External/glslang/External/spirv-tools/external/spirv-headers
    copy_external_source "${vulkanHeadersSrc}" External/Vulkan-Headers
    copy_external_source "${vulkanToolsSrc}" External/Vulkan-Tools
    copy_external_source "${volkSrc}" External/Volk

    mkdir -p External/glslang/build/include/glslang
    substituteInPlace External/glslang/glslang/OSDependent/Unix/ossource.cpp \
      --replace-fail '#include <sys/resource.h>' '#include <stdint.h>
#include <sys/resource.h>'
    (
      cd External/glslang
      python3 ./build_info.py . \
        -i build_info.h.tmpl \
        -o build/include/glslang/build_info.h
    )
    unzip -o -q -d External/glslang/External/spirv-tools Templates/spirv-tools/build.zip
    rm -rf External/glslang/External/spirv-tools/__MACOSX

    xcode_common_args=(
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
      CODE_SIGN_IDENTITY=
      COMPILER_INDEX_STORE_ENABLE=NO
      MACOSX_DEPLOYMENT_TARGET=14.0
      ONLY_ACTIVE_ARCH=NO
      ARCHS="arm64 x86_64"
      CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      LD="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      LDPLUSPLUS="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      LIBTOOL="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool"
    )

    SKIP_PACKAGING=Y /usr/bin/xcodebuild \
      GCC_PREPROCESSOR_DEFINITIONS='NDEBUG $(inherited)' \
      -project ExternalDependencies.xcodeproj \
      -scheme ExternalDependencies-macOS \
      -destination generic/platform=macOS \
      -configuration Release \
      -derivedDataPath "$PWD/External/build/Intermediates/macOS" \
      -quiet \
      SKIP_PACKAGING=Y \
      "''${xcode_common_args[@]}" \
      build

    PROJECT_DIR="$PWD" \
      CONFIGURATION=Release \
      SKIP_PACKAGING= \
      /bin/bash Scripts/create_ext_lib_xcframeworks.sh
    ln -sfn Release External/build/Latest

    /usr/bin/xcodebuild \
      -project MoltenVKPackaging.xcodeproj \
      -scheme 'MoltenVK Package (macOS only)' \
      -destination generic/platform=macOS \
      -configuration Release \
      -derivedDataPath "$PWD/build/DerivedData" \
      -quiet \
      "''${xcode_common_args[@]}" \
      build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    source_dylib="Package/Latest/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
    if [ ! -f "$source_dylib" ]; then
      echo "MoltenVK build did not produce $source_dylib" >&2
      find Package -maxdepth 6 -type f -print >&2 || true
      exit 1
    fi

    mkdir -p "$out/lib" "$out/Licenses"
    cp -f "$source_dylib" "$out/lib/libMoltenVK.dylib"
    chmod u+w "$out/lib/libMoltenVK.dylib"
    install_name_tool -id "@rpath/libMoltenVK.dylib" "$out/lib/libMoltenVK.dylib"

    if otool -L "$out/lib/libMoltenVK.dylib" |
      awk 'NR > 1 { print $1 }' |
      grep -E '^/nix/store/.*\.dylib$' >/dev/null; then
      echo "MoltenVK dylib must not reference unpackaged Nix store dylibs." >&2
      otool -L "$out/lib/libMoltenVK.dylib" >&2
      exit 1
    fi

    cp -f LICENSE "$out/Licenses/MoltenVK-Apache-2.0.txt"
    cp -f External/SPIRV-Cross/LICENSE "$out/Licenses/SPIRV-Cross-Apache-2.0.txt"
    cp -f External/cereal/LICENSE "$out/Licenses/cereal-BSD-3-Clause.txt"

    cat >"$out/SOURCE.txt" <<EOF
Component: Konyak macOS MoltenVK runtime component
Derived from: CrossOver FOSS MoltenVK source
CrossOver source URL: ${crossoverSource.url}
CrossOver source hash: ${crossoverSource.hash}
Build recipe: Nix flake in serika12345/konyak-macos-runtime
EOF

    cat >"$out/build-info.json" <<EOF
{
  "schemaVersion": 1,
  "componentId": "moltenvk",
  "version": "$version",
  "source": {
    "name": "crossover-moltenvk",
    "url": "${crossoverSource.url}",
    "hash": "${crossoverSource.hash}",
    "crossoverVersion": "${crossoverSource.version}"
  },
  "architectures": ["arm64", "x86_64"],
  "minimumMacosVersion": "14.0"
}
EOF

    runHook postInstall
  '';

  meta = {
    description = "Konyak macOS MoltenVK runtime component built from CrossOver sources";
    homepage = "https://github.com/KhronosGroup/MoltenVK";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
  };
}
