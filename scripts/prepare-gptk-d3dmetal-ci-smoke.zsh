#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

usage() {
  cat >&2 <<'EOF'
Usage: prepare-gptk-d3dmetal-ci-smoke.zsh <runtime-root> [work-root]

Downloads the pinned Gcenx Game Porting Toolkit release asset, verifies its
SHA-256, extracts the GPTK/D3DMetal payload, and imports it into the supplied
runtime root for transient CI smoke verification.

The downloaded archive and imported GPTK/D3DMetal payload must not be uploaded
as Konyak artifacts or included in runtime release assets.
EOF
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  usage
  exit 64
fi

runtime_root="$1"
work_root="${2:-${RUNNER_TEMP:-$repo_root/.dart_tool}/konyak-gptk-d3dmetal-ci-smoke}"

readonly gptk_release_tag="${KONYAK_GPTK_D3DMETAL_CI_RELEASE_TAG:-Game-Porting-Toolkit-3.0-3}"
readonly gptk_archive_name="${KONYAK_GPTK_D3DMETAL_CI_ARCHIVE_NAME:-game-porting-toolkit-3.0-3.tar.xz}"
readonly gptk_archive_sha256="${KONYAK_GPTK_D3DMETAL_CI_ARCHIVE_SHA256:-d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e}"
readonly gptk_archive_url="${KONYAK_GPTK_D3DMETAL_CI_ARCHIVE_URL:-https://github.com/Gcenx/game-porting-toolkit/releases/download/${gptk_release_tag}/${gptk_archive_name}}"

fail() {
  echo "$1" >&2
  exit "${2:-65}"
}

[[ -d "$runtime_root/lib/wine/x86_64-windows" ]] ||
  fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $runtime_root"
[[ -d "$runtime_root/lib/wine/x86_64-unix" ]] ||
  fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $runtime_root"

mkdir -p "$(dirname "$work_root")"
case "$(cd "$(dirname "$work_root")" && pwd -P)/$(basename "$work_root")" in
  "$repo_root/dist"|"$repo_root/dist"/*)
    fail "Refusing to place CI-only GPTK/D3DMetal payload under dist/: $work_root"
    ;;
esac

mkdir -p "$work_root"
archive_path="$work_root/$gptk_archive_name"
extract_root="$work_root/extract"

if [[ -f "$archive_path" ]]; then
  actual_sha256="$(shasum -a 256 "$archive_path" | awk '{ print $1 }')"
  if [[ "$actual_sha256" != "$gptk_archive_sha256" ]]; then
    rm -f "$archive_path"
  fi
fi

if [[ ! -f "$archive_path" ]]; then
  echo "Downloading CI-only GPTK/D3DMetal smoke payload from: $gptk_archive_url"
  echo "This payload is for transient verification only and is not a Konyak release artifact."
  curl \
    --fail \
    --location \
    --proto '=https' \
    --retry 3 \
    --retry-delay 5 \
    --show-error \
    --silent \
    --tlsv1.2 \
    --output "$archive_path" \
    "$gptk_archive_url"
fi

actual_sha256="$(shasum -a 256 "$archive_path" | awk '{ print $1 }')"
if [[ "$actual_sha256" != "$gptk_archive_sha256" ]]; then
  fail "GPTK/D3DMetal CI archive SHA-256 mismatch: expected $gptk_archive_sha256, got $actual_sha256"
fi

rm -rf "$extract_root"
mkdir -p "$extract_root"
tar --warning=no-unknown-keyword -xaf "$archive_path" -C "$extract_root"

gptk_wine_lib="$extract_root/Game Porting Toolkit.app/Contents/Resources/wine/lib"
gptk_license="$gptk_wine_lib/external/D3DMetal.framework/Versions/A/Resources/LICENSE"
[[ -d "$gptk_wine_lib/external" && -d "$gptk_wine_lib/wine" ]] ||
  fail "Could not find Gcenx GPTK Wine library layout in extracted archive: $gptk_wine_lib"
[[ -f "$gptk_license" ]] ||
  fail "Gcenx GPTK/D3DMetal archive is missing D3DMetal license resource: $gptk_license"

"$repo_root/scripts/import-gptk-d3dmetal-redist.zsh" \
  "$gptk_wine_lib" \
  "$runtime_root"

echo "Prepared CI-only GPTK/D3DMetal smoke payload from $gptk_release_tag."
