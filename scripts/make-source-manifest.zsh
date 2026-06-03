#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
release_dir="${1:-$repo_root/result-release}"
runtime_archive="${2:-}"

if [[ -z "$runtime_archive" || ! -f "$runtime_archive" ]]; then
  echo "Usage: $0 <release-dir> <runtime-archive>" >&2
  exit 64
fi

mkdir -p "$release_dir"
source_json="$repo_root/sources/crossover.json"
version="$(jq -r '.version' "$source_json")"
archive_name="$(basename "$runtime_archive")"
sha256="$(shasum -a 256 "$runtime_archive" | awk '{ print $1 }')"

jq -n \
  --arg archive "$archive_name" \
  --arg sha256 "$sha256" \
  --arg version "crossover-${version}-konyak.0" \
  '{
    schemaVersion: 1,
    runtimeId: "konyak-macos-wine",
    stackId: "macos-konyak-runtime-stack",
    components: [
      {
        id: "wine",
        version: $version,
        archiveUrl: $archive,
        sha256: $sha256
      }
    ]
  }' >"$release_dir/konyak-macos-wine-runtime-stack-source.json"
