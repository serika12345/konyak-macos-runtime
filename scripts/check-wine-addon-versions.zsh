#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_json="$repo_root/sources/crossover.json"
package_script="$repo_root/scripts/package-binary-components.zsh"
addon_check_script="$repo_root/scripts/check-wine-addons-component.zsh"
cache_dir="${KONYAK_COMPONENT_DOWNLOAD_CACHE:-$repo_root/.component-cache}"

json_value() {
  local key="$1"
  python3 - "$source_json" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
value = payload.get(sys.argv[2], "")
if not isinstance(value, str) or not value.strip():
    raise SystemExit(f"missing {sys.argv[2]} in {sys.argv[1]}")
print(value)
PY
}

sha256_hex_from_sri() {
  python3 - "$1" <<'PY'
import base64
import sys

value = sys.argv[1]
prefix = "sha256-"
if not value.startswith(prefix):
    raise SystemExit(f"unsupported hash format: {value}")
print(base64.b64decode(value[len(prefix):]).hex())
PY
}

sha256_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

extract_readonly_value() {
  local name="$1"
  sed -n "s/^readonly ${name}=\"\\([^\"]*\\)\"$/\\1/p" "$package_script"
}

require_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "$label mismatch: expected $expected, got $actual" >&2
    exit 65
  fi
}

version="$(json_value version)"
source_url="$(json_value url)"
expected_archive_sha="$(sha256_hex_from_sri "$(json_value hash)")"
archive_path="$cache_dir/crossover-sources-$version.tar.gz"

mkdir -p "$cache_dir"
if [[ ! -f "$archive_path" ]]; then
  curl --fail --location --output "$archive_path" "$source_url"
fi

actual_archive_sha="$(sha256_file "$archive_path")"
require_equal "CrossOver source archive checksum" \
  "${expected_archive_sha:l}" \
  "${actual_archive_sha:l}"

addons_source_path="$(
  tar -tzf "$archive_path" |
    grep -E '/dlls/appwiz.cpl/addons.c$' |
    head -n 1
)"
if [[ -z "$addons_source_path" ]]; then
  echo "Unable to find Wine addon source in CrossOver source archive." >&2
  exit 65
fi

mono_version="$(
  tar -xOzf "$archive_path" "$addons_source_path" |
    sed -n 's/^#define MONO_VERSION "\([^"]*\)".*$/\1/p'
)"
gecko_version="$(
  tar -xOzf "$archive_path" "$addons_source_path" |
    sed -n 's/^#define GECKO_VERSION "\([^"]*\)".*$/\1/p'
)"
if [[ -z "$mono_version" || -z "$gecko_version" ]]; then
  echo "Unable to extract MONO_VERSION or GECKO_VERSION from $addons_source_path." >&2
  exit 65
fi

package_mono_version="$(extract_readonly_value wine_mono_version)"
package_gecko_version="$(extract_readonly_value wine_gecko_version)"
require_equal "wine_mono_version" "$mono_version" "$package_mono_version"
require_equal "wine_gecko_version" "$gecko_version" "$package_gecko_version"

for expected_path in \
  "share/wine/mono/wine-mono-$mono_version-x86.msi" \
  "share/wine/gecko/wine-gecko-$gecko_version-x86.msi" \
  "share/wine/gecko/wine-gecko-$gecko_version-x86_64.msi"; do
  if ! grep -Fq "$expected_path" "$addon_check_script"; then
    echo "Addon check script does not require $expected_path." >&2
    exit 65
  fi
done

echo "Wine addon versions match CrossOver source: mono $mono_version, gecko $gecko_version"
