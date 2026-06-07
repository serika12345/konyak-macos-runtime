#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"

if [[ -z "$runtime_root" || ! -d "$runtime_root" ]]; then
  echo "Usage: $0 <runtime-root>" >&2
  exit 64
fi

required_paths=(
  "lib/wine/i386-windows/ntdll.dll"
  "lib/wine/x86_64-windows/wow64.dll"
  "lib/wine/x86_64-windows/wow64cpu.dll"
  "lib/wine/x86_64-windows/wow64win.dll"
)

host_unix_ntdll_candidates=(
  "lib/wine/x86_64-unix/ntdll.so"
  "lib/wine/aarch64-unix/ntdll.so"
)

for relative_path in "${required_paths[@]}"; do
  if [[ ! -e "$runtime_root/$relative_path" ]]; then
    echo "Missing Wine32-on-64 runtime path: $relative_path" >&2
    exit 65
  fi
done

if [[ -e "$runtime_root/lib/wine/i386-unix/ntdll.so" ]]; then
  echo "Unexpected i386 Unix Wine host path in Wine32-on-64 runtime." >&2
  exit 65
fi

host_unix_ntdll_path=""
for candidate_path in "${host_unix_ntdll_candidates[@]}"; do
  if [[ -e "$runtime_root/$candidate_path" ]]; then
    host_unix_ntdll_path="$candidate_path"
    break
  fi
done

if [[ -z "$host_unix_ntdll_path" ]]; then
  echo "Missing Wine32-on-64 host Unix ntdll path: ${host_unix_ntdll_candidates[*]}" >&2
  exit 65
fi

assert_file_kind() {
  local relative_path="$1"
  local expected_pattern="$2"
  local description="$3"
  local file_output

  file_output="$(/usr/bin/file "$runtime_root/$relative_path")"
  if [[ "$file_output" != *"$expected_pattern"* ]]; then
    echo "$description has unexpected file type:" >&2
    echo "$file_output" >&2
    exit 65
  fi
}

assert_file_kind "lib/wine/i386-windows/ntdll.dll" "PE32 executable" \
  "i386 Windows ntdll.dll"
assert_file_kind "lib/wine/x86_64-windows/wow64.dll" "PE32+ executable" \
  "x86_64 Windows wow64.dll"
assert_file_kind "lib/wine/x86_64-windows/wow64cpu.dll" "PE32+ executable" \
  "x86_64 Windows wow64cpu.dll"
assert_file_kind "lib/wine/x86_64-windows/wow64win.dll" "PE32+ executable" \
  "x86_64 Windows wow64win.dll"
assert_file_kind "$host_unix_ntdll_path" "Mach-O 64-bit" \
  "host Unix ntdll.so"

echo "Wine32-on-64 runtime layout OK: $runtime_root"
