#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
release_dir="${1:-$repo_root/result-release}"
runtime_archive="${2:-}"
shift 2 || true
component_specs=("$@")

if [[ -z "$runtime_archive" || ! -f "$runtime_archive" ]]; then
  echo "Usage: $0 <release-dir> <runtime-archive> [component-id=archive ...]" >&2
  exit 64
fi

mkdir -p "$release_dir"
source_json="$repo_root/sources/crossover.json"
version="$(jq -r '.version' "$source_json")"
archive_name="$(basename "$runtime_archive")"
sha256="$(shasum -a 256 "$runtime_archive" | awk '{ print $1 }')"
asset_base_url="${KONYAK_RELEASE_ASSET_BASE_URL:-}"
single_stack_archive="${KONYAK_SINGLE_STACK_ARCHIVE:-0}"
archive_url="$archive_name"
if [[ -n "$asset_base_url" ]]; then
  archive_url="${asset_base_url%/}/$archive_name"
fi

component_version() {
  local component_id="$1"
  case "$component_id" in
    dxmt)
      echo "$(jq -r '.version' "$repo_root/sources/dxmt.json")-konyak.0"
      ;;
    vkd3d)
      echo "crossover-${version}-vkd3d-1.18-konyak.0"
      ;;
    dxvk-macos)
      echo "v1.10.3-20230507+dxvk-1.10.3-d3d10"
      ;;
    moltenvk)
      echo "v1.4.1"
      ;;
    gstreamer)
      echo "nix-gstreamer+plugins"
      ;;
    freetype)
      echo "nix-freetype"
      ;;
    wine-mono)
      echo "wine-mono-11.1.0"
      ;;
    winetricks)
      echo "20260125"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

component_archive_url() {
  local archive_path="$1"
  local archive_name
  archive_name="$(basename "$archive_path")"
  local url="$archive_name"
  if [[ -n "$asset_base_url" ]]; then
    url="${asset_base_url%/}/$archive_name"
  fi
  echo "$url"
}

components_json="$(
  jq -n \
    --arg archive "$archive_url" \
    --arg sha256 "$sha256" \
    --arg version "crossover-${version}-konyak.0" \
    '[{
      id: "wine",
      version: $version,
      archiveUrl: $archive,
      sha256: $sha256
    }]'
)"

for spec in "${component_specs[@]}"; do
  component_id="${spec%%=*}"
  component_archive="${spec#*=}"
  if [[ "$component_id" == "$component_archive" ]]; then
    component_id="dxmt"
  fi
  if [[ ! -f "$component_archive" ]]; then
    echo "Component archive does not exist for $component_id: $component_archive" >&2
    exit 66
  fi

  component_sha256="$(shasum -a 256 "$component_archive" | awk '{ print $1 }')"
  component_url="$(component_archive_url "$component_archive")"
  if [[ "$single_stack_archive" = "1" ]]; then
    component_sha256="$sha256"
    component_url="$archive_url"
  fi
  component_archive_version="$(component_version "$component_id")"
  components_json="$(
    jq \
      --arg id "$component_id" \
      --arg archive "$component_url" \
      --arg sha256 "$component_sha256" \
      --arg version "$component_archive_version" \
      '. + [{
        id: $id,
        version: $version,
        archiveUrl: $archive,
        sha256: $sha256
      }]' <<<"$components_json"
  )"
done

jq -n \
  --argjson components "$components_json" \
  '{
    schemaVersion: 1,
    runtimeId: "konyak-macos-wine",
    stackId: "macos-konyak-runtime-stack",
    components: $components
  }' >"$release_dir/konyak-macos-wine-runtime-stack-source.json"

jq -n \
  --arg version "crossover-${version}-konyak.0" \
  '{
    schemaVersion: 1,
    appId: "konyak",
    version: $version,
    runtimeStack: {
      runtimeId: "konyak-macos-wine",
      stackId: "macos-konyak-runtime-stack",
      sourceManifestFileName: "konyak-macos-wine-runtime-stack-source.json"
    }
  }' >"$release_dir/konyak-macos-runtime.release.json"
