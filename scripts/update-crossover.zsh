#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_page="${CROSSOVER_SOURCE_PAGE:-https://www.codeweavers.com/crossover/source}"
base_url="${CROSSOVER_SOURCE_BASE_URL:-https://media.codeweavers.com/pub/crossover/source}"

latest="$(
  curl -fsSL "$source_page" |
    grep -Eo 'crossover-sources-[0-9][^"<> ]+\.tar\.gz' |
    sed -E 's/^crossover-sources-//; s/\.tar\.gz$//' |
    sort -V |
    tail -1
)"

if [[ -z "$latest" ]]; then
  echo "Failed to resolve latest CrossOver source version." >&2
  exit 1
fi

archive="crossover-sources-${latest}.tar.gz"
url="${base_url}/${archive}"
prefetch_json="$(nix store prefetch-file --json "$url")"
hash="$(jq -r '.hash' <<<"$prefetch_json")"

jq -n \
  --arg version "$latest" \
  --arg url "$url" \
  --arg hash "$hash" \
  '{version: $version, url: $url, hash: $hash}' \
  >"$repo_root/sources/crossover.json"

echo "Pinned CrossOver source ${latest}"
