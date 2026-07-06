#!/usr/bin/env zsh
set -euo pipefail

component_root="${1:-}"

if [[ -z "$component_root" || ! -d "$component_root" ]]; then
  echo "Usage: $0 <moltenvk-component-root-or-assembled-runtime-root>" >&2
  exit 64
fi

dylib_path="$component_root/lib/libMoltenVK.dylib"
if [[ ! -f "$dylib_path" ]]; then
  echo "Missing MoltenVK component path: lib/libMoltenVK.dylib" >&2
  find "$component_root" -maxdepth 3 -type f -print >&2
  exit 65
fi

file_output="$(/usr/bin/file "$dylib_path")"
if [[ "$file_output" != *"Mach-O universal binary"* ||
      "$file_output" != *"x86_64"* ||
      "$file_output" != *"arm64"* ]]; then
  echo "MoltenVK dylib must be a universal x86_64/arm64 macOS dylib:" >&2
  echo "$file_output" >&2
  exit 65
fi

lipo_output="$(/usr/bin/lipo -info "$dylib_path")"
if [[ "$lipo_output" != *"x86_64"* || "$lipo_output" != *"arm64"* ]]; then
  echo "MoltenVK dylib does not contain both x86_64 and arm64 slices:" >&2
  echo "$lipo_output" >&2
  exit 65
fi

install_name="$(otool -D "$dylib_path" | tail -n 1)"
if [[ "$install_name" != "@rpath/libMoltenVK.dylib" ]]; then
  echo "MoltenVK dylib install name must be @rpath/libMoltenVK.dylib, got: $install_name" >&2
  exit 65
fi

references="$(
  otool -L "$dylib_path" |
    awk 'NR > 1 && $1 ~ /^\/nix\/store\/.*\.dylib$/ { print $1 }'
  otool -l "$dylib_path" |
    awk '/LC_RPATH/ { getline; getline; if ($2 ~ /^\/nix\/store\//) print $2 }'
)"
if [[ -n "$references" ]]; then
  echo "MoltenVK dylib must not reference unpackaged Nix store dylibs or rpaths:" >&2
  echo "$references" >&2
  exit 65
fi

if [[ -f "$component_root/.konyak-runtime-stack.json" ]]; then
  version="$(
    nix shell nixpkgs#jq -c jq -r '.components.moltenvk // empty' \
      "$component_root/.konyak-runtime-stack.json"
  )"
  if [[ -z "$version" ]]; then
    echo "MoltenVK runtime stack manifest must contain components.moltenvk." >&2
    exit 65
  fi
fi

echo "MoltenVK component layout OK: $component_root"
