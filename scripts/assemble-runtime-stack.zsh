#!/usr/bin/env zsh
set -euo pipefail

dist_dir="${1:-}"
runtime_root="${2:-}"

if [[ -z "$dist_dir" || -z "$runtime_root" ]]; then
  echo "Usage: $0 <dist-dir> <assembled-runtime-root>" >&2
  exit 64
fi

if [[ ! -d "$dist_dir" ]]; then
  echo "Runtime artifact dist directory does not exist: $dist_dir" >&2
  exit 65
fi

case "$runtime_root" in
  ""|"/"|".")
    echo "Refusing unsafe runtime assembly root: $runtime_root" >&2
    exit 65
    ;;
esac

dist_dir="$(cd "$dist_dir" && pwd -P)"
runtime_parent="$(dirname "$runtime_root")"
mkdir -p "$runtime_parent"
runtime_parent="$(cd "$runtime_parent" && pwd -P)"
runtime_root="$runtime_parent/$(basename "$runtime_root")"

archives=(
  konyak-macos-wine-runtime.tar.zst
  konyak-macos-dxmt.tar.zst
  konyak-macos-vkd3d.tar.zst
  konyak-macos-dxvk-macos.tar.zst
  konyak-macos-moltenvk.tar.zst
  konyak-macos-gstreamer.tar.zst
  konyak-macos-freetype.tar.zst
  konyak-macos-wine-mono.tar.zst
  konyak-macos-winetricks.tar.zst
)

for archive in "${archives[@]}"; do
  if [[ ! -f "$dist_dir/$archive" ]]; then
    echo "Missing runtime artifact archive: $dist_dir/$archive" >&2
    exit 65
  fi
done

rm -rf "$runtime_root"
mkdir -p "$runtime_root"

nix shell nixpkgs#gnutar -c tar \
  -xaf "$dist_dir/konyak-macos-wine-runtime.tar.zst" \
  -C "$runtime_root"
chmod -R u+w "$runtime_root"

component_archives=(
  konyak-macos-dxmt.tar.zst
  konyak-macos-vkd3d.tar.zst
  konyak-macos-dxvk-macos.tar.zst
  konyak-macos-moltenvk.tar.zst
  konyak-macos-gstreamer.tar.zst
  konyak-macos-freetype.tar.zst
  konyak-macos-wine-mono.tar.zst
  konyak-macos-winetricks.tar.zst
)
for component_archive in "${component_archives[@]}"; do
  nix shell nixpkgs#gnutar -c tar \
    -xaf "$dist_dir/$component_archive" \
    -C "$runtime_root"
done

echo "Runtime stack assembled: $runtime_root"
