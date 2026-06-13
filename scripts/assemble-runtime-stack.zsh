#!/usr/bin/env zsh
set -euo pipefail

dist_dir="${1:-}"
runtime_root="${2:-}"
stack_archive="${3:-}"

if [[ -z "$dist_dir" || -z "$runtime_root" ]]; then
  echo "Usage: $0 <dist-dir> <assembled-runtime-root> [stack-archive]" >&2
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
if [[ -n "$stack_archive" ]]; then
  stack_archive_parent="$(dirname "$stack_archive")"
  mkdir -p "$stack_archive_parent"
  stack_archive_parent="$(cd "$stack_archive_parent" && pwd -P)"
  stack_archive="$stack_archive_parent/$(basename "$stack_archive")"
fi

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

merged_components_json="{}"

merge_component_version() {
  local component_id="$1"
  local component_version="$2"

  merged_components_json="$(
    nix shell nixpkgs#jq -c jq -n \
      --argjson existing "$merged_components_json" \
      --arg component_id "$component_id" \
      --arg component_version "$component_version" \
      '$existing * {($component_id): $component_version}'
  )"
}

merge_runtime_stack_manifest() {
  local manifest_path="$runtime_root/.konyak-runtime-stack.json"

  if [[ ! -f "$manifest_path" ]]; then
    return
  fi

  merged_components_json="$(
    nix shell nixpkgs#jq -c jq -n \
      --argjson existing "$merged_components_json" \
      --slurpfile manifest "$manifest_path" \
      '$existing * ($manifest[0].components // {})'
  )"
}

write_runtime_stack_manifest() {
  nix shell nixpkgs#jq -c jq -n \
    --argjson components "$merged_components_json" \
    '{
      schemaVersion: 1,
      components: $components
    }' >"$runtime_root/.konyak-runtime-stack.json"
}

nix shell nixpkgs#gnutar -c tar \
  -xaf "$dist_dir/konyak-macos-wine-runtime.tar.zst" \
  -C "$runtime_root"
chmod -R u+w "$runtime_root"
if [[ -f "$runtime_root/build-info.json" ]]; then
  wine_version="$(nix shell nixpkgs#jq -c jq -r '.version // empty' "$runtime_root/build-info.json")"
  if [[ -n "$wine_version" ]]; then
    merge_component_version "wine" "$wine_version"
  fi
fi
merge_runtime_stack_manifest

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
  merge_runtime_stack_manifest
done

write_runtime_stack_manifest

echo "Runtime stack assembled: $runtime_root"

if [[ -n "$stack_archive" ]]; then
  rm -f "$stack_archive"
  nix shell nixpkgs#gnutar -c tar \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mode='u+rwX,go+rX' \
    -C "$runtime_root" \
    -caf "$stack_archive" \
    .
  echo "Runtime stack archive: $stack_archive"
fi
