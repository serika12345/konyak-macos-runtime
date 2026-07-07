#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"
release_version="${2:-}"

if [[ -z "$runtime_root" || -z "$release_version" ]]; then
  echo "Usage: $0 <runtime-root> <release-version>" >&2
  exit 64
fi

if [[ ! -d "$runtime_root" ]]; then
  echo "Runtime root does not exist: $runtime_root" >&2
  exit 66
fi

build_info="$runtime_root/build-info.json"
if [[ ! -f "$build_info" ]]; then
  echo "Runtime build-info.json does not exist: $build_info" >&2
  exit 66
fi

tmp_build_info="$(mktemp)"
tmp_stack_manifest="$(mktemp)"
trap 'rm -f "$tmp_build_info" "$tmp_stack_manifest"' EXIT

jq -e --arg version "$release_version" '
  if .schemaVersion == 1 and .componentId == "wine" then
    .version = $version
  else
    error("runtime build-info.json does not describe the Wine component")
  end
' "$build_info" >"$tmp_build_info"
mv "$tmp_build_info" "$build_info"

stack_manifest="$runtime_root/.konyak-runtime-stack.json"
if [[ -f "$stack_manifest" ]]; then
  jq -e --arg version "$release_version" '
    .schemaVersion = 1
    | .components = ((.components // {}) + {wine: $version})
  ' "$stack_manifest" >"$tmp_stack_manifest"
else
  jq -n --arg version "$release_version" '{
    schemaVersion: 1,
    components: {
      wine: $version
    }
  }' >"$tmp_stack_manifest"
fi
mv "$tmp_stack_manifest" "$stack_manifest"

echo "Stamped Wine runtime release version: $release_version"
