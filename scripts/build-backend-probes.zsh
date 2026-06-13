#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
output_dir="${1:-$repo_root/.dart_tool/backend-probes}"
compiler="${KONYAK_MINGW_CC:-x86_64-w64-mingw32-gcc}"

if ! command -v "$compiler" >/dev/null 2>&1; then
  echo "Missing $compiler. Run through the runtime Nix dev shell." >&2
  exit 2
fi

mkdir -p "$output_dir"

"$compiler" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -O2 \
  "$repo_root/probes/windows/d3d11_device_probe.c" \
  -o "$output_dir/d3d11_device_probe.exe"

"$compiler" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -O2 \
  "$repo_root/probes/windows/d3d12_device_probe.c" \
  -o "$output_dir/d3d12_device_probe.exe"

"$compiler" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -O2 \
  -mwindows \
  -municode \
  "$repo_root/probes/windows/gui_launch_probe.c" \
  -o "$output_dir/gui_launch_probe.exe"

printf '%s\n' "$output_dir"
