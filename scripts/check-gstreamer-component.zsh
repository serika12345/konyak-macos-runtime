#!/usr/bin/env zsh
set -euo pipefail

component_root="${1:-}"

if [[ -z "$component_root" || ! -d "$component_root" ]]; then
  echo "Usage: $0 <gstreamer-component-root-or-assembled-runtime-root>" >&2
  exit 64
fi

component_root="$(cd "$component_root" && pwd -P)"

required_paths=(
  lib/libgstreamer-1.0.0.dylib
  lib/gstreamer-1.0/libgstcoreelements.dylib
  lib/gstreamer-1.0/libgstplayback.dylib
  lib/gstreamer-1.0/libgsttypefindfunctions.dylib
  lib/gstreamer-1.0/libgstisomp4.dylib
  lib/gstreamer-1.0/libgstwavparse.dylib
  lib/gstreamer-1.0/libgstapplemedia.dylib
  libexec/gstreamer-1.0/gst-plugin-scanner
)

for relative_path in "${required_paths[@]}"; do
  if [[ ! -e "$component_root/$relative_path" ]]; then
    echo "Missing GStreamer component path: $relative_path" >&2
    exit 65
  fi
done

require_x86_64_macho() {
  local path="$1"
  local label="$2"
  local file_output

  file_output="$(/usr/bin/file "$path")"
  if [[ "$file_output" != *"Mach-O 64-bit"* || "$file_output" != *"x86_64"* ]]; then
    echo "$label is not an x86_64 Mach-O binary:" >&2
    echo "$file_output" >&2
    exit 65
  fi
}

find_macho_nix_dylib_references() {
  local candidate_path
  local file_output

  /usr/bin/find "$component_root/lib" "$component_root/libexec" -type f -print |
    while IFS= read -r candidate_path; do
      file_output="$(/usr/bin/file "$candidate_path")"
      case "$file_output" in
        *Mach-O*) ;;
        *) continue ;;
      esac

      otool -L "$candidate_path" |
        awk -v relative_path="${candidate_path#$component_root/}" \
          'NR > 1 && $1 ~ /^\/nix\/store\/.*\.dylib$/ { print relative_path ": " $1 }'

      otool -l "$candidate_path" |
        awk -v relative_path="${candidate_path#$component_root/}" \
          '/LC_RPATH/ { getline; getline; if ($2 ~ /^\/nix\/store\//) print relative_path ": " $2 }'
    done
}

require_x86_64_macho "$component_root/lib/libgstreamer-1.0.0.dylib" \
  "GStreamer library"
require_x86_64_macho "$component_root/libexec/gstreamer-1.0/gst-plugin-scanner" \
  "GStreamer plugin scanner"

for plugin_path in "$component_root"/lib/gstreamer-1.0/*.dylib; do
  require_x86_64_macho "$plugin_path" "GStreamer plugin ${plugin_path:t}"
done

nix_references="$(find_macho_nix_dylib_references)"
if [[ -n "$nix_references" ]]; then
  echo "GStreamer component Mach-O files must not reference unpackaged Nix store dylibs:" >&2
  echo "$nix_references" >&2
  exit 65
fi

echo "GStreamer component layout OK: $component_root"
