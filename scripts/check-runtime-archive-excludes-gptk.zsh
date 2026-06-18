#!/usr/bin/env zsh
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 <runtime-stack-archive.tar.zst>" >&2
  exit 64
fi

archive_path="$1"
[[ -f "$archive_path" ]] || {
  echo "Runtime stack archive does not exist: $archive_path" >&2
  exit 66
}

if ! tar --version 2>/dev/null | grep -q 'GNU tar'; then
  echo "GNU tar not found. Run this script inside nix develop." >&2
  exit 69
fi

forbidden_entries="$(
  tar -tf "$archive_path" |
    grep -E '(^|/)components/gptk-d3dmetal(/|$)|(^|/)lib/external/(D3DMetal\.framework(/|$)|libd3dshared\.dylib$)|(^|/)lib/wine/x86_64-(windows|unix)/(atidxx64|nvapi64|nvngx|nvngx-on-metalfx)\.(dll|so)$' ||
    true
)"

if [[ -n "$forbidden_entries" ]]; then
  echo "Runtime archive must not include GPTK/D3DMetal payload paths:" >&2
  echo "$forbidden_entries" >&2
  exit 65
fi

echo "Runtime archive excludes GPTK/D3DMetal payloads: $archive_path"
