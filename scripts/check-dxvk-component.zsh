#!/usr/bin/env zsh
set -euo pipefail

component_root="${1:-}"

if [[ -z "$component_root" || ! -d "$component_root" ]]; then
  echo "Usage: $0 <dxvk-component-root-or-assembled-runtime-root>" >&2
  exit 64
fi

if [[ -d "$component_root/lib/dxvk" ]]; then
  component_root="$component_root/lib/dxvk"
fi

dll_names=(
  dxgi.dll
  d3d9.dll
  d3d10.dll
  d3d10_1.dll
  d3d10core.dll
  d3d11.dll
)

required_paths=()
for dll_name in "${dll_names[@]}"; do
  required_paths+=("x86_64-windows/$dll_name")
  required_paths+=("i386-windows/$dll_name")
done

for relative_path in "${required_paths[@]}"; do
  if [[ ! -f "$component_root/$relative_path" ]]; then
    echo "Missing DXVK component path: $relative_path" >&2
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

for dll_name in "${dll_names[@]}"; do
  assert_file_kind "x86_64-windows/$dll_name" "PE32+ executable" \
    "x86_64 DXVK $dll_name"
  assert_file_kind "i386-windows/$dll_name" "PE32 executable" \
    "i386 DXVK $dll_name"
done

echo "DXVK component layout OK: $component_root"
