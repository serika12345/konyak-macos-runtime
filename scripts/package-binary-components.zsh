#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
dist_dir="${1:-$repo_root/dist}"
gstreamer_root="${2:-}"
freetype_root="${3:-}"
cache_dir="${KONYAK_COMPONENT_DOWNLOAD_CACHE:-$repo_root/.component-cache}"

resolve_gnu_tar() {
  if command -v gtar >/dev/null 2>&1; then
    command -v gtar
    return 0
  fi

  if tar --version 2>/dev/null | grep -q 'GNU tar'; then
    command -v tar
    return 0
  fi

  echo "GNU tar is required. Run through nix shell nixpkgs#gnutar or install gtar." >&2
  return 1
}

readonly tar_bin="$(resolve_gnu_tar)"

readonly dxvk_version="v1.10.3-20230507"
readonly dxvk_url="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507/dxvk-macOS-async-v1.10.3-20230507.tar.gz"
readonly dxvk_sha256="f67d99d0a8eeedd7d406b283a3df9f939b5965acb00efcb33d0c6235c195a516"

readonly moltenvk_version="v1.4.1"
readonly moltenvk_url="https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.1/MoltenVK-macos.tar"
readonly moltenvk_sha256="5ea0c259df7ded9a275444820f09cced54d6e5a7c7a31d262de62a5cdb7e15cf"

readonly wine_mono_version="11.1.0"
readonly wine_mono_url="https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.1.0/wine-mono-11.1.0-x86.msi"
readonly wine_mono_sha256="deb0341431f8260b209fff6bc79ddcc5414b97f8e9236ab9fbdca4ce59e0a9b9"

readonly winetricks_version="20260125"
readonly winetricks_url="https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks"
readonly winetricks_sha256="431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

if [[ -z "$gstreamer_root" || ! -d "$gstreamer_root" ||
      -z "$freetype_root" || ! -d "$freetype_root" ]]; then
  echo "Usage: $0 <dist-dir> <gstreamer-root> <freetype-root>" >&2
  exit 64
fi

mkdir -p "$dist_dir" "$cache_dir"

sha256_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

download_if_missing() {
  local url="$1"
  local target="$2"
  local expected_sha256="$3"
  local actual_sha256

  if [[ ! -f "$target" ]]; then
    mkdir -p "$(dirname "$target")"
    curl --fail --location --output "$target" "$url"
  fi

  actual_sha256="$(sha256_file "$target")"
  if [[ "${actual_sha256:l}" != "${expected_sha256:l}" ]]; then
    echo "checksum mismatch for $target: expected $expected_sha256, got $actual_sha256" >&2
    exit 65
  fi
}

reset_dir() {
  rm -rf "$1"
  mkdir -p "$1"
}

write_stack_manifest() {
  local target="$1"
  local component_id="$2"
  local version="$3"

  jq -n \
    --arg component_id "$component_id" \
    --arg version "$version" \
    '{
      schemaVersion: 1,
      components: {
        ($component_id): $version
      }
    }' >"$target"
}

archive_payload() {
  local payload_root="$1"
  local archive_path="$2"

  rm -f "$archive_path"
  "$tar_bin" \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mode='u+rwX,go+rX' \
    -C "$payload_root" \
    -caf "$archive_path" \
    .
}

copy_nix_dylib_closure() {
  local source_path="$1"
  local target_dir="$2"
  local file_name="${source_path:t}"
  local target_path="${target_dir}/${file_name}"
  local dependency
  local dependency_file_name

  if [[ ! -f "$source_path" ]]; then
    echo "dylib not found: $source_path" >&2
    exit 65
  fi

  if [[ -f "$target_path" ]]; then
    return 0
  fi

  mkdir -p "$target_dir"
  cp -Lf "$source_path" "$target_path"
  chmod u+w "$target_path"
  install_name_tool -id "@rpath/$file_name" "$target_path" 2>/dev/null || true

  otool -L "$source_path" |
    awk 'NR > 1 { print $1 }' |
    while IFS= read -r dependency; do
      if [[ "$dependency" == "$source_path" ||
            "$dependency" != /nix/store/* ||
            "$dependency" != *.dylib ]]; then
        continue
      fi

      copy_nix_dylib_closure "$dependency" "$target_dir"
      dependency_file_name="${dependency:t}"
      install_name_tool \
        -change "$dependency" "@loader_path/$dependency_file_name" \
        "$target_path"
    done
}

package_dxvk_macos() {
  local archive_cache="$cache_dir/dxvk-macOS-async-$dxvk_version.tar.gz"
  local work_root="$dist_dir/work/dxvk-macos"
  local extract_root="$work_root/extract"
  local payload_root="$work_root/payload"
  local archive_path="$dist_dir/konyak-macos-dxvk-macos.tar.zst"

  download_if_missing "$dxvk_url" "$archive_cache" "$dxvk_sha256"
  reset_dir "$work_root"
  mkdir -p \
    "$extract_root" \
    "$payload_root/lib/dxvk/x86_64-windows" \
    "$payload_root/lib/dxvk/i386-windows"
  "$tar_bin" --warning=no-unknown-keyword -xzf "$archive_cache" -C "$extract_root"

  for dll_name in dxgi.dll d3d9.dll d3d10core.dll d3d11.dll; do
    local source_x64
    local source_x32
    source_x64="$(find "$extract_root" -path "*/x64/$dll_name" -type f | head -n 1)"
    source_x32="$(find "$extract_root" -path "*/x32/$dll_name" -type f | head -n 1)"
    if [[ -z "$source_x64" || -z "$source_x32" ]]; then
      echo "DXVK-macOS archive does not contain x64/x32 $dll_name." >&2
      exit 65
    fi
    cp -f "$source_x64" "$payload_root/lib/dxvk/x86_64-windows/$dll_name"
    cp -f "$source_x32" "$payload_root/lib/dxvk/i386-windows/$dll_name"
  done

  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "dxvk-macos" "$dxvk_version"
  archive_payload "$payload_root" "$archive_path"
}

package_moltenvk() {
  local archive_cache="$cache_dir/MoltenVK-macos-$moltenvk_version.tar"
  local work_root="$dist_dir/work/moltenvk"
  local extract_root="$work_root/extract"
  local payload_root="$work_root/payload"
  local archive_path="$dist_dir/konyak-macos-moltenvk.tar.zst"
  local source_dylib

  download_if_missing "$moltenvk_url" "$archive_cache" "$moltenvk_sha256"
  reset_dir "$work_root"
  mkdir -p "$extract_root" "$payload_root/lib"
  "$tar_bin" -xf "$archive_cache" -C "$extract_root"
  source_dylib="$(find "$extract_root" -path '*/dynamic/dylib/macOS/libMoltenVK.dylib' -type f | head -n 1)"
  if [[ -z "$source_dylib" ]]; then
    echo "MoltenVK archive does not contain macOS libMoltenVK.dylib." >&2
    exit 65
  fi

  cp -f "$source_dylib" "$payload_root/lib/libMoltenVK.dylib"
  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "moltenvk" "$moltenvk_version"
  archive_payload "$payload_root" "$archive_path"
}

package_gstreamer() {
  local payload_root="$dist_dir/work/gstreamer/payload"
  local archive_path="$dist_dir/konyak-macos-gstreamer.tar.zst"
  local source_dylib="$gstreamer_root/lib/libgstreamer-1.0.0.dylib"

  if [[ ! -f "$source_dylib" ]]; then
    echo "GStreamer dylib not found: $source_dylib" >&2
    exit 65
  fi

  reset_dir "$dist_dir/work/gstreamer"
  mkdir -p "$payload_root/lib"
  cp -Lf "$source_dylib" "$payload_root/lib/libgstreamer-1.0.0.dylib"
  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "gstreamer" "$(basename "$gstreamer_root")"
  archive_payload "$payload_root" "$archive_path"
}

package_freetype() {
  local payload_root="$dist_dir/work/freetype/payload"
  local archive_path="$dist_dir/konyak-macos-freetype.tar.zst"
  local source_dylib="$freetype_root/lib/libfreetype.6.dylib"

  if [[ ! -f "$source_dylib" ]]; then
    echo "FreeType dylib not found: $source_dylib" >&2
    exit 65
  fi

  reset_dir "$dist_dir/work/freetype"
  copy_nix_dylib_closure "$source_dylib" "$payload_root/lib"
  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "freetype" "$(basename "$freetype_root")"
  archive_payload "$payload_root" "$archive_path"
}

package_wine_mono() {
  local archive_cache="$cache_dir/wine-mono-$wine_mono_version-x86.msi"
  local payload_root="$dist_dir/work/wine-mono/payload"
  local archive_path="$dist_dir/konyak-macos-wine-mono.tar.zst"

  download_if_missing "$wine_mono_url" "$archive_cache" "$wine_mono_sha256"
  reset_dir "$dist_dir/work/wine-mono"
  mkdir -p "$payload_root/share/wine/mono"
  cp -f "$archive_cache" "$payload_root/share/wine/mono/wine-mono-$wine_mono_version-x86.msi"
  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "wine-mono" "wine-mono-$wine_mono_version"
  archive_payload "$payload_root" "$archive_path"
}

package_winetricks() {
  local script_cache="$cache_dir/winetricks-$winetricks_version"
  local payload_root="$dist_dir/work/winetricks/payload"
  local archive_path="$dist_dir/konyak-macos-winetricks.tar.zst"

  download_if_missing "$winetricks_url" "$script_cache" "$winetricks_sha256"
  reset_dir "$dist_dir/work/winetricks"
  mkdir -p "$payload_root"
  cp -f "$script_cache" "$payload_root/winetricks"
  chmod 0755 "$payload_root/winetricks"
  write_stack_manifest "$payload_root/.konyak-runtime-stack.json" "winetricks" "$winetricks_version"
  archive_payload "$payload_root" "$archive_path"
}

package_dxvk_macos
package_moltenvk
package_gstreamer
package_freetype
package_wine_mono
package_winetricks

rm -rf "$dist_dir/work"
