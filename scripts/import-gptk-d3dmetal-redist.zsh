#!/usr/bin/env zsh
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: import-gptk-d3dmetal-redist.zsh <gptk-3.0-dmg-or-redist-dir> <runtime-root>

Overlays Apple GPTK/D3DMetal redist files into a Konyak macOS Wine runtime.
The source may be either:

- Game_Porting_Toolkit_3.0.dmg
- the nested "Evaluation environment for Windows games 3.0.dmg"
- an already mounted/extracted redist directory
EOF
}

if [[ "$#" -ne 2 ]]; then
  usage
  exit 64
fi

source_path="$1"
runtime_root="$2"
mount_roots=()
mounted_dmg_root=
redist_root=

cleanup() {
  local index
  for (( index=${#mount_roots[@]}; index>=1; index-- )); do
    hdiutil detach "${mount_roots[$index]}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit "${2:-65}"
}

mount_dmg() {
  local dmg_path="$1"
  local mount_root
  mount_root="$(mktemp -d "${TMPDIR:-/tmp}/konyak-gptk-mount.XXXXXX")"
  hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$mount_root" >/dev/null
  mount_roots+=("$mount_root")
  mounted_dmg_root="$mount_root"
}

find_redist() {
  local candidate="$1"
  local mounted
  local nested

  if [[ -d "$candidate" ]]; then
    if [[ -d "$candidate/external" && -d "$candidate/wine" ]]; then
      redist_root="$candidate"
      return 0
    fi

    if [[ -d "$candidate/lib/external" && -d "$candidate/lib/wine" ]]; then
      redist_root="$candidate/lib"
      return 0
    fi

    nested="$(find "$candidate" -maxdepth 3 -type d -name redist | head -n 1)"
    if [[ -n "$nested" && -d "$nested/lib/external" && -d "$nested/lib/wine" ]]; then
      redist_root="$nested/lib"
      return 0
    fi

    nested="$candidate/Contents/SharedSupport/CrossOver/lib64/apple_gptk"
    if [[ -d "$nested/external" && -d "$nested/wine" ]]; then
      redist_root="$nested"
      return 0
    fi
  fi

  if [[ -f "$candidate" && "$candidate" == *.dmg ]]; then
    mount_dmg "$candidate"
    mounted="$mounted_dmg_root"

    nested="$(find "$mounted" -maxdepth 3 -type d -name redist | head -n 1)"
    if [[ -n "$nested" && -d "$nested/lib/external" && -d "$nested/lib/wine" ]]; then
      redist_root="$nested/lib"
      return 0
    fi

    nested="$(find "$mounted" -maxdepth 2 -type f -name '*.dmg' | head -n 1)"
    if [[ -n "$nested" ]]; then
      find_redist "$nested"
      return 0
    fi
  fi

  return 1
}

require_path() {
  local path="$1"
  [[ -e "$path" ]] || fail "GPTK redist is missing required path: $path"
}

require_symlink() {
  local path="$1"
  local target="$2"
  local actual_target

  [[ -L "$path" ]] || fail "GPTK redist path must be a symlink: $path"
  actual_target="$(/usr/bin/stat -f '%Y' "$path")"
  [[ "$actual_target" == "$target" ]] ||
    fail "GPTK redist symlink target mismatch for $path: expected $target, got $actual_target"
}

resolve_redist_path() {
  local relative_path="$1"
  local candidate
  local -a candidates

  candidates=("$relative_path")
  case "$relative_path" in
    wine/x86_64-windows/nvngx.dll)
      candidates=(wine/x86_64-windows/nvngx.dll wine/x86_64-windows/nvngx-on-metalfx.dll)
      ;;
    wine/x86_64-unix/nvngx.so)
      candidates=(wine/x86_64-unix/nvngx.so wine/x86_64-unix/nvngx-on-metalfx.so)
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if [[ -e "$redist_root/$candidate" ]]; then
      print -r -- "$redist_root/$candidate"
      return 0
    fi
  done

  return 1
}

find_redist "$source_path" ||
  fail "Could not find GPTK redist payload in: $source_path"

[[ -d "$runtime_root/lib/wine/x86_64-windows" ]] ||
  fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $runtime_root"
[[ -d "$runtime_root/lib/wine/x86_64-unix" ]] ||
  fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $runtime_root"

required_paths=(
  external/D3DMetal.framework
  external/libd3dshared.dylib
  wine/x86_64-windows/atidxx64.dll
  wine/x86_64-windows/d3d11.dll
  wine/x86_64-windows/d3d12.dll
  wine/x86_64-windows/dxgi.dll
  wine/x86_64-windows/nvapi64.dll
  wine/x86_64-windows/nvngx.dll
  wine/x86_64-unix/atidxx64.so
  wine/x86_64-unix/d3d11.so
  wine/x86_64-unix/d3d12.so
  wine/x86_64-unix/dxgi.so
  wine/x86_64-unix/nvapi64.so
  wine/x86_64-unix/nvngx.so
)

local_path=
source_local_path=
for local_path in "${required_paths[@]}"; do
  source_local_path="$(resolve_redist_path "$local_path")" ||
    fail "GPTK redist is missing required path: $redist_root/$local_path"
  require_path "$source_local_path"
done

require_symlink "$redist_root/wine/x86_64-unix/d3d11.so" "../../external/libd3dshared.dylib"
require_symlink "$redist_root/wine/x86_64-unix/d3d12.so" "../../external/libd3dshared.dylib"
require_symlink "$redist_root/wine/x86_64-unix/dxgi.so" "../../external/libd3dshared.dylib"

mkdir -p \
  "$runtime_root/lib/external" \
  "$runtime_root/lib/wine/x86_64-windows" \
  "$runtime_root/lib/wine/x86_64-unix"

rsync -a --delete "$redist_root/external/" "$runtime_root/lib/external/"
rsync -a "$redist_root/wine/x86_64-windows/" "$runtime_root/lib/wine/x86_64-windows/"

for local_path in \
  atidxx64.dll \
  d3d11.dll \
  d3d12.dll \
  dxgi.dll \
  nvapi64.dll \
  nvngx.dll
do
  source_local_path="$(resolve_redist_path "wine/x86_64-windows/$local_path")"
  rm -f "$runtime_root/lib/wine/x86_64-windows/$local_path"
  cp -a "$source_local_path" "$runtime_root/lib/wine/x86_64-windows/$local_path"
done

for local_path in \
  atidxx64.so \
  d3d11.so \
  d3d12.so \
  dxgi.so \
  nvapi64.so \
  nvngx.so
do
  source_local_path="$(resolve_redist_path "wine/x86_64-unix/$local_path")"
  rm -f "$runtime_root/lib/wine/x86_64-unix/$local_path"
  cp -a "$source_local_path" "$runtime_root/lib/wine/x86_64-unix/$local_path"
done

xattr -dr com.apple.quarantine \
  "$runtime_root/lib/external" \
  "$runtime_root/lib/wine/x86_64-windows" \
  "$runtime_root/lib/wine/x86_64-unix" 2>/dev/null || true

require_symlink "$runtime_root/lib/wine/x86_64-unix/d3d11.so" "../../external/libd3dshared.dylib"
require_symlink "$runtime_root/lib/wine/x86_64-unix/d3d12.so" "../../external/libd3dshared.dylib"
require_symlink "$runtime_root/lib/wine/x86_64-unix/dxgi.so" "../../external/libd3dshared.dylib"

echo "Imported GPTK/D3DMetal redist into: $runtime_root"
