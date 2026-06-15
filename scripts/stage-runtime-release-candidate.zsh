#!/usr/bin/env zsh
original_path="${PATH:-}"
emulate -L zsh
export PATH="$original_path"
path=("${(@s.:.)original_path}")
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

dry_run=false
candidate_tag=""
dist_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    -*)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
    *)
      if [[ -z "$candidate_tag" ]]; then
        candidate_tag="$1"
      elif [[ -z "$dist_dir" ]]; then
        dist_dir="$1"
      else
        echo "unexpected argument: $1" >&2
        exit 64
      fi
      shift
      ;;
  esac
done

if [[ -z "$candidate_tag" ]]; then
  echo "Usage: $0 [--dry-run] <candidate-tag> [dist-dir]" >&2
  exit 64
fi

if [[ "$candidate_tag" == crossover-* ]]; then
  echo "Candidate tag must not be the final runtime release tag: $candidate_tag" >&2
  exit 64
fi

dist_dir="${dist_dir:-$repo_root/dist}"
release_metadata="$dist_dir/konyak-macos-runtime.release.json"
source_manifest="$dist_dir/konyak-macos-wine-runtime-stack-source.json"
runtime_stack="$dist_dir/konyak-macos-wine-runtime-stack.tar.zst"

for asset_path in "$release_metadata" "$source_manifest" "$runtime_stack"; do
  if [[ ! -f "$asset_path" ]]; then
    echo "missing runtime release candidate asset: $asset_path" >&2
    exit 66
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Run this script inside nix develop." >&2
  exit 69
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found. Install GitHub CLI or run inside an environment that provides it." >&2
  exit 69
fi

release_tag="$(
  jq -er '
    if (.version | type == "string" and length > 0) then
      .version
    else
      error("release metadata must contain a non-empty version.")
    end
  ' "$release_metadata"
)"

jq -e --arg release_tag "$release_tag" '
  .schemaVersion == 1 and
  .appId == "konyak" and
  .version == $release_tag and
  .runtimeStack.runtimeId == "konyak-macos-wine" and
  .runtimeStack.stackId == "macos-konyak-runtime-stack" and
  .runtimeStack.sourceManifestFileName == "konyak-macos-wine-runtime-stack-source.json"
' "$release_metadata" >/dev/null || {
  echo "release metadata does not match the macOS runtime release contract." >&2
  exit 65
}

jq -e '
  .schemaVersion == 1 and
  .runtimeId == "konyak-macos-wine" and
  .stackId == "macos-konyak-runtime-stack" and
  (.components | type) == "array"
' "$source_manifest" >/dev/null || {
  echo "source manifest does not match the macOS runtime stack contract." >&2
  exit 65
}

missing_components="$(
  jq -r '
    [
      "wine",
      "dxvk-macos",
      "moltenvk",
      "gstreamer",
      "freetype",
      "wine-mono",
      "wine-gecko",
      "winetricks",
      "vkd3d",
      "dxmt"
    ] as $required
    | ([.components[] | select(type == "object") | .id] | unique) as $present
    | ($required - $present)[]
  ' "$source_manifest"
)"
if [[ -n "$missing_components" ]]; then
  echo "source manifest missing required component ids:" >&2
  echo "$missing_components" >&2
  exit 65
fi

if [[ "$dry_run" == true ]]; then
  echo "Runtime candidate assets are valid for $candidate_tag -> $release_tag."
  exit 0
fi

if gh release view "$candidate_tag" >/dev/null 2>&1; then
  gh release upload "$candidate_tag" \
    "$release_metadata" \
    "$source_manifest" \
    "$runtime_stack" \
    --clobber
  gh release edit "$candidate_tag" \
    --draft=true \
    --prerelease=true \
    --title "Konyak macOS runtime candidate $candidate_tag" \
    --notes "Candidate assets for $release_tag. Promote through the CI candidate workflow before publishing the final runtime release."
else
  gh release create "$candidate_tag" \
    "$release_metadata" \
    "$source_manifest" \
    "$runtime_stack" \
    --draft \
    --prerelease \
    --target "$(git -C "$repo_root" rev-parse HEAD)" \
    --title "Konyak macOS runtime candidate $candidate_tag" \
    --notes "Candidate assets for $release_tag. Promote through the CI candidate workflow before publishing the final runtime release."
fi

echo "Staged runtime release candidate: $candidate_tag"
echo "Promote with:"
echo "  gh workflow run 'Promote runtime candidate' --field candidate_tag=$candidate_tag"
