#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
release_dir="${1:-$repo_root/result-release}"
runtime_archive="${2:-}"
dxmt_archive="${3:-}"

if [[ -z "$runtime_archive" || ! -f "$runtime_archive" ]]; then
  echo "Usage: $0 <release-dir> <runtime-archive> [dxmt-archive]" >&2
  exit 64
fi

mkdir -p "$release_dir"
source_json="$repo_root/sources/crossover.json"
version="$(jq -r '.version' "$source_json")"
archive_name="$(basename "$runtime_archive")"
sha256="$(shasum -a 256 "$runtime_archive" | awk '{ print $1 }')"
asset_base_url="${KONYAK_RELEASE_ASSET_BASE_URL:-}"
archive_url="$archive_name"
if [[ -n "$asset_base_url" ]]; then
  archive_url="${asset_base_url%/}/$archive_name"
fi

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

if [[ -n "$dxmt_archive" ]]; then
  if [[ ! -f "$dxmt_archive" ]]; then
    echo "DXMT archive does not exist: $dxmt_archive" >&2
    exit 66
  fi

  dxmt_archive_name="$(basename "$dxmt_archive")"
  dxmt_sha256="$(shasum -a 256 "$dxmt_archive" | awk '{ print $1 }')"
  dxmt_url="$dxmt_archive_name"
  if [[ -n "$asset_base_url" ]]; then
    dxmt_url="${asset_base_url%/}/$dxmt_archive_name"
  fi
  dxmt_version="$(jq -r '.version' "$repo_root/sources/dxmt.json")-konyak.0"
  components_json="$(
    jq \
      --arg archive "$dxmt_url" \
      --arg sha256 "$dxmt_sha256" \
      --arg version "$dxmt_version" \
      '. + [{
        id: "dxmt",
        version: $version,
        archiveUrl: $archive,
        sha256: $sha256
      }]' <<<"$components_json"
  )"
fi

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
