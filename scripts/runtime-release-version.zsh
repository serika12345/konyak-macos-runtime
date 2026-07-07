#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_json="$repo_root/sources/crossover.json"

crossover_version="$(jq -r '.version // empty' "$source_json")"
konyak_revision="$(jq -r '.konyakRevision // 0' "$source_json")"

if [[ -z "$crossover_version" ]]; then
  echo "sources/crossover.json version must be a non-empty string." >&2
  exit 65
fi

case "$konyak_revision" in
  (''|*[!0-9]*)
    echo "sources/crossover.json konyakRevision must be a non-negative integer." >&2
    exit 65
    ;;
esac

printf 'crossover-%s-konyak.%s\n' "$crossover_version" "$konyak_revision"
