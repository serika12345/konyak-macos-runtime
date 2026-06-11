#!/usr/bin/env zsh
set -euo pipefail

component_root="${1:-}"

if [[ -z "$component_root" || ! -d "$component_root" ]]; then
  echo "Usage: $0 <vkd3d-component-root-or-assembled-runtime-root>" >&2
  exit 64
fi

if [[ -d "$component_root/lib/wine" ]]; then
  component_root="$component_root/lib/wine"
fi

dll_names=(
  libvkd3d-1.dll
  libvkd3d-shader-1.dll
  libvkd3d-utils-1.dll
)

required_paths=()
for dll_name in "${dll_names[@]}"; do
  required_paths+=("x86_64-windows/$dll_name")
  required_paths+=("i386-windows/$dll_name")
done

for relative_path in "${required_paths[@]}"; do
  if [[ ! -f "$component_root/$relative_path" ]]; then
    echo "Missing vkd3d component path: $relative_path" >&2
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
    "x86_64 vkd3d $dll_name"
  assert_file_kind "i386-windows/$dll_name" "PE32 executable" \
    "i386 vkd3d $dll_name"
done

echo "vkd3d component layout OK: $component_root"
