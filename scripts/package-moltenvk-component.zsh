#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
moltenvk_root="${1:-}"
dist_dir="${2:-$repo_root/dist}"

if [[ -z "$moltenvk_root" || ! -d "$moltenvk_root" ]]; then
  echo "Usage: $0 <moltenvk-build-result-root> [dist-dir]" >&2
  exit 64
fi

if [[ ! -f "$moltenvk_root/lib/libMoltenVK.dylib" ]]; then
  echo "MoltenVK build result does not contain lib/libMoltenVK.dylib: $moltenvk_root" >&2
  exit 65
fi

if [[ ! -f "$moltenvk_root/build-info.json" ]]; then
  echo "MoltenVK build result does not contain build-info.json: $moltenvk_root" >&2
  exit 65
fi

resolve_gnu_tar() {
  if command -v gtar >/dev/null 2>&1; then
    command -v gtar
    return 0
  fi

  if tar --version 2>/dev/null | grep -q 'GNU tar'; then
    command -v tar
    return 0
  fi

  echo "GNU tar is required. Run through nix shell nixpkgs#gnutar or install gtar." >&2
  return 1
}

tar_bin="$(resolve_gnu_tar)" || exit 65
readonly tar_bin

version="$(nix shell nixpkgs#jq -c jq -r '.version // empty' "$moltenvk_root/build-info.json")"
if [[ -z "$version" ]]; then
  echo "MoltenVK build-info.json did not contain a version." >&2
  exit 65
fi

work_root="$dist_dir/work/moltenvk"
payload_root="$work_root/payload"
archive_path="$dist_dir/konyak-macos-moltenvk.tar.zst"

rm -rf "$work_root"
mkdir -p "$payload_root/lib" "$payload_root/Licenses" "$dist_dir"
cp -f "$moltenvk_root/lib/libMoltenVK.dylib" "$payload_root/lib/libMoltenVK.dylib"
if [[ -d "$moltenvk_root/Licenses" ]]; then
  cp -R "$moltenvk_root/Licenses/." "$payload_root/Licenses/"
fi
cp -f "$moltenvk_root/build-info.json" "$payload_root/build-info.json"
if [[ -f "$moltenvk_root/SOURCE.txt" ]]; then
  cp -f "$moltenvk_root/SOURCE.txt" "$payload_root/SOURCE.txt"
fi

nix shell nixpkgs#jq -c jq -n \
  --arg version "$version" \
  '{
    schemaVersion: 1,
    components: {
      moltenvk: $version
    }
  }' >"$payload_root/.konyak-runtime-stack.json"

"$repo_root/scripts/check-moltenvk-component.zsh" "$payload_root"

rm -f "$archive_path"
"$tar_bin" \
  --sort=name \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mode='u+rwX,go+rX' \
  -C "$payload_root" \
  -caf "$archive_path" \
  .

rm -rf "$work_root"
echo "MoltenVK component archive: $archive_path"
