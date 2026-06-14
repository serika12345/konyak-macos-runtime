#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"

if [[ -z "$runtime_root" || ! -d "$runtime_root" ]]; then
  echo "Usage: $0 <assembled-runtime-root>" >&2
  exit 64
fi

sha256_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

assert_payload_sha256() {
  local relative_path="$1"
  local expected_sha256="$2"
  local payload_path="$runtime_root/$relative_path"
  local actual_sha256

  if [[ ! -f "$payload_path" ]]; then
    echo "Missing Wine addon payload: $relative_path" >&2
    exit 65
  fi

  actual_sha256="$(sha256_file "$payload_path")"
  if [[ "${actual_sha256:l}" != "${expected_sha256:l}" ]]; then
    echo "Wine addon payload checksum mismatch for $relative_path:" >&2
    echo "  expected: $expected_sha256" >&2
    echo "  actual:   $actual_sha256" >&2
    exit 65
  fi
}

assert_payload_sha256 \
  "share/wine/mono/wine-mono-10.4.1-x86.msi" \
  "071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23"
assert_payload_sha256 \
  "share/wine/gecko/wine-gecko-2.47.4-x86.msi" \
  "26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6"
assert_payload_sha256 \
  "share/wine/gecko/wine-gecko-2.47.4-x86_64.msi" \
  "e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f"

echo "Wine addon payloads OK: $runtime_root"
