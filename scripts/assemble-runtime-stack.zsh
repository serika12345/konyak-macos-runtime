#!/usr/bin/env zsh
set -euo pipefail

dist_dir="${1:-}"
runtime_root="${2:-}"
stack_archive="${3:-}"

if [[ -z "$dist_dir" || -z "$runtime_root" ]]; then
  echo "Usage: $0 <dist-dir> <assembled-runtime-root> [stack-archive]" >&2
  exit 64
fi

if [[ ! -d "$dist_dir" ]]; then
  echo "Runtime artifact dist directory does not exist: $dist_dir" >&2
  exit 65
fi

case "$runtime_root" in
  ""|"/"|".")
    echo "Refusing unsafe runtime assembly root: $runtime_root" >&2
    exit 65
    ;;
esac

dist_dir="$(cd "$dist_dir" && pwd -P)"
runtime_parent="$(dirname "$runtime_root")"
mkdir -p "$runtime_parent"
runtime_parent="$(cd "$runtime_parent" && pwd -P)"
runtime_root="$runtime_parent/$(basename "$runtime_root")"
if [[ -n "$stack_archive" ]]; then
  stack_archive_parent="$(dirname "$stack_archive")"
  mkdir -p "$stack_archive_parent"
  stack_archive_parent="$(cd "$stack_archive_parent" && pwd -P)"
  stack_archive="$stack_archive_parent/$(basename "$stack_archive")"
fi

archives=(
  konyak-macos-wine-runtime.tar.zst
  konyak-macos-dxmt.tar.zst
  konyak-macos-vkd3d.tar.zst
  konyak-macos-dxvk-macos.tar.zst
  konyak-macos-moltenvk.tar.zst
  konyak-macos-gstreamer.tar.zst
  konyak-macos-freetype.tar.zst
  konyak-macos-wine-mono.tar.zst
  konyak-macos-winetricks.tar.zst
)

for archive in "${archives[@]}"; do
  if [[ ! -f "$dist_dir/$archive" ]]; then
    echo "Missing runtime artifact archive: $dist_dir/$archive" >&2
    exit 65
  fi
done

rm -rf "$runtime_root"
mkdir -p "$runtime_root"

merged_components_json="{}"

merge_component_version() {
  local component_id="$1"
  local component_version="$2"

  merged_components_json="$(
    nix shell nixpkgs#jq -c jq -n \
      --argjson existing "$merged_components_json" \
      --arg component_id "$component_id" \
      --arg component_version "$component_version" \
      '$existing * {($component_id): $component_version}'
  )"
}

merge_runtime_stack_manifest() {
  local manifest_path="$runtime_root/.konyak-runtime-stack.json"

  if [[ ! -f "$manifest_path" ]]; then
    return
  fi

  merged_components_json="$(
    nix shell nixpkgs#jq -c jq -n \
      --argjson existing "$merged_components_json" \
      --slurpfile manifest "$manifest_path" \
      '$existing * ($manifest[0].components // {})'
  )"
}

write_runtime_stack_manifest() {
  nix shell nixpkgs#jq -c jq -n \
    --argjson components "$merged_components_json" \
    '{
      schemaVersion: 1,
      components: $components
    }' >"$runtime_root/.konyak-runtime-stack.json"
}

ensure_wine64_alias() {
  if [[ -e "$runtime_root/bin/wine64" ]]; then
    return
  fi
  if [[ ! -e "$runtime_root/bin/wine" ]]; then
    echo "Cannot create wine64 alias because bin/wine is missing." >&2
    exit 65
  fi

  (
    cd "$runtime_root/bin"
    ln -s wine wine64
  )
}

iconv_guard_dir="$(mktemp -d)"
trap 'rm -rf "$iconv_guard_dir"' EXIT

preserve_root_iconv_runtime() {
  local library_name

  for library_name in libiconv.2.dylib libiconv.dylib libiconv-darwin.2.dylib; do
    if [[ ! -f "$runtime_root/lib/$library_name" ]]; then
      echo "Missing Wine root iconv runtime library: $runtime_root/lib/$library_name" >&2
      exit 65
    fi

    cp -Lf "$runtime_root/lib/$library_name" "$iconv_guard_dir/$library_name"
  done
}

restore_root_iconv_runtime() {
  local library_name

  for library_name in libiconv.2.dylib libiconv.dylib libiconv-darwin.2.dylib; do
    cp -f "$iconv_guard_dir/$library_name" "$runtime_root/lib/$library_name"
    chmod u+w "$runtime_root/lib/$library_name"
  done
}

is_macho_file() {
  local candidate_path="$1"
  local file_output

  file_output="$(/usr/bin/file "$candidate_path")"
  case "$file_output" in
    *Mach-O*) return 0 ;;
    *) return 1 ;;
  esac
}

darwin_iconv_dependency_refs() {
  local target_path="$1"
  local line
  local dependency

  otool -L "$target_path" |
    while IFS= read -r line; do
      case "$line" in
        *"compatibility version 7.0.0, current version 7.0.0)"*) ;;
        *) continue ;;
      esac

      dependency="$(
        printf '%s\n' "$line" |
          sed 's/^[[:space:]]*//; s/[[:space:]]*(compatibility version.*$//'
      )"
      case "$dependency" in
        */libiconv.2.dylib|libiconv.2.dylib)
          printf '%s\n' "$dependency"
          ;;
      esac
    done
}

root_iconv_replacement_for() {
  local target_path="$1"

  case "$target_path" in
    "$runtime_root/bin/"*)
      printf '%s\n' "@loader_path/../lib/libiconv-darwin.2.dylib"
      ;;
    "$runtime_root/lib/"*)
      printf '%s\n' "@loader_path/libiconv-darwin.2.dylib"
      ;;
    *)
      return 1
      ;;
  esac
}

patch_root_darwin_iconv_dependents() {
  local search_dir
  local candidate_path
  local dependencies
  local dependency
  local replacement_reference

  for search_dir in "$runtime_root/bin" "$runtime_root/lib"; do
    [[ -d "$search_dir" ]] || continue

    for candidate_path in "$search_dir"/*(N); do
      [[ -f "$candidate_path" ]] || continue
      is_macho_file "$candidate_path" || continue

      dependencies="$(darwin_iconv_dependency_refs "$candidate_path")"
      [[ -n "$dependencies" ]] || continue

      replacement_reference="$(root_iconv_replacement_for "$candidate_path")"
      chmod u+w "$candidate_path"
      printf '%s\n' "$dependencies" |
        while IFS= read -r dependency; do
          install_name_tool \
            -change "$dependency" "$replacement_reference" \
            "$candidate_path"
        done
    done
  done
}

nix shell nixpkgs#gnutar -c tar \
  -xaf "$dist_dir/konyak-macos-wine-runtime.tar.zst" \
  -C "$runtime_root"
chmod -R u+w "$runtime_root"
preserve_root_iconv_runtime
if [[ -f "$runtime_root/build-info.json" ]]; then
  wine_version="$(nix shell nixpkgs#jq -c jq -r '.version // empty' "$runtime_root/build-info.json")"
  if [[ -n "$wine_version" ]]; then
    merge_component_version "wine" "$wine_version"
  fi
fi
merge_runtime_stack_manifest

component_archives=(
  konyak-macos-dxmt.tar.zst
  konyak-macos-vkd3d.tar.zst
  konyak-macos-dxvk-macos.tar.zst
  konyak-macos-moltenvk.tar.zst
  konyak-macos-gstreamer.tar.zst
  konyak-macos-freetype.tar.zst
  konyak-macos-wine-mono.tar.zst
  konyak-macos-winetricks.tar.zst
)
for component_archive in "${component_archives[@]}"; do
  nix shell nixpkgs#gnutar -c tar \
    -xaf "$dist_dir/$component_archive" \
    -C "$runtime_root"
  merge_runtime_stack_manifest
done

restore_root_iconv_runtime
patch_root_darwin_iconv_dependents
write_runtime_stack_manifest
ensure_wine64_alias

echo "Runtime stack assembled: $runtime_root"

if [[ -n "$stack_archive" ]]; then
  rm -f "$stack_archive"
  nix shell nixpkgs#gnutar -c tar \
    --sort=name \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --mode='u+rwX,go+rX' \
    -C "$runtime_root" \
    -caf "$stack_archive" \
    .
  echo "Runtime stack archive: $stack_archive"
fi
