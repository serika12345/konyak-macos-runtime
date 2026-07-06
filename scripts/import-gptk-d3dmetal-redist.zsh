#!/usr/bin/env zsh
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: import-gptk-d3dmetal-redist.zsh <gptk-dmg-or-redist-dir> <runtime-root>

Overlays Apple GPTK/D3DMetal redist files into a Konyak macOS Wine runtime.
The source may be either:

- Game_Porting_Toolkit_3.0.dmg
- Game_Porting_Toolkit_4.0_beta_1.dmg
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

d3dmetal_info_plist() {
  local candidate

  for candidate in \
    "$redist_root/external/D3DMetal.framework/Versions/A/Resources/Info.plist" \
    "$redist_root/external/D3DMetal.framework/Resources/Info.plist" \
    "$redist_root/external/D3DMetal.framework/Info.plist"
  do
    if [[ -f "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}

plist_string_value() {
  local plist_path="$1"
  local key="$2"
  local value

  if [[ -x /usr/libexec/PlistBuddy ]]; then
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      print -r -- "$value"
      return 0
    fi
  fi

  if command -v plutil >/dev/null 2>&1; then
    value="$(plutil -extract "$key" raw -o - "$plist_path" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      print -r -- "$value"
      return 0
    fi
  fi

  sed -n \
    -e "s/.*<key>$key<\\/key>[[:space:]]*<string>\\([^<]*\\)<\\/string>.*/\\1/p" \
    -e "/<key>$key<\\/key>/{n;s/.*<string>\\([^<]*\\)<\\/string>.*/\\1/p;q;}" \
    "$plist_path"
}

detect_gptk_payload_version() {
  local info_plist
  local framework_version
  local normalized_version

  info_plist="$(d3dmetal_info_plist)" || {
    echo "D3DMetal.framework does not contain GPTK version metadata." >&2
    return 1
  }
  framework_version="$(plist_string_value "$info_plist" CFBundleShortVersionString)"
  if [[ -z "$framework_version" ]]; then
    echo "D3DMetal.framework does not contain GPTK version metadata." >&2
    return 1
  fi
  normalized_version="${framework_version:l}"

  case "$normalized_version" in
    3|3.*|3b*)
      print -r -- "gptk3"
      ;;
    4|4.*|4b*)
      print -r -- "gptk4"
      ;;
    *)
      echo "Unsupported GPTK/D3DMetal framework version: $framework_version" >&2
      return 1
      ;;
  esac
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

component_root="$runtime_root/components/gptk-d3dmetal"
gptk_payload_version="$(detect_gptk_payload_version)" || exit 65

required_paths=(
  external/D3DMetal.framework
  external/libd3dshared.dylib
  wine/x86_64-windows/d3d11.dll
  wine/x86_64-windows/d3d12.dll
  wine/x86_64-windows/dxgi.dll
  wine/x86_64-windows/nvapi64.dll
  wine/x86_64-windows/nvngx.dll
  wine/x86_64-unix/d3d11.so
  wine/x86_64-unix/d3d12.so
  wine/x86_64-unix/dxgi.so
  wine/x86_64-unix/nvapi64.so
  wine/x86_64-unix/nvngx.so
)
if [[ "$gptk_payload_version" == "gptk3" ]]; then
  required_paths+=(
    wine/x86_64-windows/atidxx64.dll
    wine/x86_64-unix/atidxx64.so
  )
fi

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

rm -rf "$component_root"
mkdir -p \
  "$component_root/lib/external" \
  "$component_root/lib/wine/x86_64-windows" \
  "$component_root/lib/wine/x86_64-unix"

rsync -a --delete "$redist_root/external/" "$component_root/lib/external/"

windows_payloads=(
  d3d11.dll
  d3d12.dll
  dxgi.dll
  nvapi64.dll
  nvngx.dll
)
if [[ "$gptk_payload_version" == "gptk3" ]]; then
  windows_payloads=(atidxx64.dll "${windows_payloads[@]}")
fi

for local_path in "${windows_payloads[@]}"; do
  source_local_path="$(resolve_redist_path "wine/x86_64-windows/$local_path")"
  rm -f "$component_root/lib/wine/x86_64-windows/$local_path"
  cp -a "$source_local_path" "$component_root/lib/wine/x86_64-windows/$local_path"
done

unix_payloads=(
  d3d11.so
  d3d12.so
  dxgi.so
  nvapi64.so
  nvngx.so
)
if [[ "$gptk_payload_version" == "gptk3" ]]; then
  unix_payloads=(atidxx64.so "${unix_payloads[@]}")
fi

for local_path in "${unix_payloads[@]}"; do
  source_local_path="$(resolve_redist_path "wine/x86_64-unix/$local_path")"
  rm -f "$component_root/lib/wine/x86_64-unix/$local_path"
  cp -a "$source_local_path" "$component_root/lib/wine/x86_64-unix/$local_path"
done

xattr -dr com.apple.quarantine \
  "$component_root/lib/external" \
  "$component_root/lib/wine/x86_64-windows" \
  "$component_root/lib/wine/x86_64-unix" 2>/dev/null || true

require_symlink "$component_root/lib/wine/x86_64-unix/d3d11.so" "../../external/libd3dshared.dylib"
require_symlink "$component_root/lib/wine/x86_64-unix/d3d12.so" "../../external/libd3dshared.dylib"
require_symlink "$component_root/lib/wine/x86_64-unix/dxgi.so" "../../external/libd3dshared.dylib"

echo "Imported GPTK/D3DMetal redist into: $component_root"
echo "Detected GPTK/D3DMetal payload version: $gptk_payload_version"
