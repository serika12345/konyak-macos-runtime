#!/usr/bin/env zsh
set -euo pipefail

component_root="${1:-}"

if [[ -z "$component_root" || ! -d "$component_root" ]]; then
  echo "Usage: $0 <dxmt-component-root-or-assembled-runtime-root>" >&2
  exit 64
fi

if [[ -d "$component_root/lib/dxmt" ]]; then
  component_root="$component_root/lib/dxmt"
fi

required_paths=(
  "x86_64-windows/winemetal.dll"
  "x86_64-windows/d3d11.dll"
  "x86_64-windows/dxgi.dll"
  "x86_64-windows/d3d10core.dll"
  "x86_64-windows/nvapi64.dll"
  "x86_64-windows/nvngx.dll"
  "i386-windows/winemetal.dll"
  "i386-windows/d3d11.dll"
  "i386-windows/dxgi.dll"
  "i386-windows/d3d10core.dll"
  "x86_64-unix/winemetal.so"
)

for relative_path in "${required_paths[@]}"; do
  if [[ ! -f "$component_root/$relative_path" ]]; then
    echo "Missing DXMT component path: $relative_path" >&2
    find "$component_root" -maxdepth 3 -type f -print >&2
    exit 65
  fi
done

assert_file_kind() {
  local relative_path="$1"
  local expected_pattern="$2"
  local description="$3"
  local file_output

  file_output="$(/usr/bin/file "$component_root/$relative_path")"
  if [[ "$file_output" != *"$expected_pattern"* ]]; then
    echo "$description has unexpected file type:" >&2
    echo "$file_output" >&2
    exit 65
  fi
}

for dll_name in winemetal.dll d3d11.dll dxgi.dll d3d10core.dll; do
  assert_file_kind "x86_64-windows/$dll_name" "PE32+ executable" \
    "x86_64 DXMT $dll_name"
  assert_file_kind "i386-windows/$dll_name" "PE32 executable" \
    "i386 DXMT $dll_name"
done

for dll_name in nvapi64.dll nvngx.dll; do
  assert_file_kind "x86_64-windows/$dll_name" "PE32+ executable" \
    "x86_64 DXMT $dll_name"
done

assert_file_kind "x86_64-unix/winemetal.so" "Mach-O 64-bit" \
  "x86_64 Unix DXMT winemetal.so"

find_macho_nix_dylib_references() {
  local candidate_path
  local relative_path
  local file_output

  find "$component_root/x86_64-unix" -type f -print |
    while IFS= read -r candidate_path; do
      file_output="$(/usr/bin/file "$candidate_path")"
      if [[ "$file_output" != *"Mach-O"* ]]; then
        continue
      fi

      relative_path="${candidate_path#$component_root/}"
      otool -L "$candidate_path" |
        awk -v relative_path="$relative_path" \
          'NR > 1 && $1 ~ /^\/nix\/store\/.*\.dylib$/ { print relative_path ": " $1 }'

      otool -l "$candidate_path" |
        awk -v relative_path="$relative_path" \
          '/LC_RPATH/ { getline; getline; if ($2 ~ /^\/nix\/store\//) print relative_path ": " $2 }'
    done
}

nix_dylib_references="$(find_macho_nix_dylib_references)"
if [[ -n "$nix_dylib_references" ]]; then
  echo "DXMT component Mach-O files must not reference unpackaged Nix store dylibs:" >&2
  echo "$nix_dylib_references" >&2
  exit 65
fi

echo "DXMT component layout OK: $component_root"
