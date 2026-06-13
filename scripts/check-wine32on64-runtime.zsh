#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"

if [[ -z "$runtime_root" || ! -d "$runtime_root" ]]; then
  echo "Usage: $0 <runtime-root>" >&2
  exit 64
fi

required_paths=(
  "bin/wine"
  "bin/wine64"
  "bin/wineserver"
  "lib/wine/i386-windows/cmd.exe"
  "lib/wine/i386-windows/kernel32.dll"
  "lib/wine/i386-windows/ntdll.dll"
  "lib/wine/x86_64-windows/cmd.exe"
  "lib/wine/x86_64-windows/kernel32.dll"
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
assert_file_kind "lib/wine/i386-windows/kernel32.dll" "PE32 executable" \
  "i386 Windows kernel32.dll"
assert_file_kind "lib/wine/i386-windows/cmd.exe" "PE32 executable" \
  "i386 Windows cmd.exe"
assert_file_kind "lib/wine/x86_64-windows/kernel32.dll" "PE32+ executable" \
  "x86_64 Windows kernel32.dll"
assert_file_kind "lib/wine/x86_64-windows/cmd.exe" "PE32+ executable" \
  "x86_64 Windows cmd.exe"
assert_file_kind "lib/wine/x86_64-windows/wow64.dll" "PE32+ executable" \
  "x86_64 Windows wow64.dll"
assert_file_kind "lib/wine/x86_64-windows/wow64cpu.dll" "PE32+ executable" \
  "x86_64 Windows wow64cpu.dll"
assert_file_kind "lib/wine/x86_64-windows/wow64win.dll" "PE32+ executable" \
  "x86_64 Windows wow64win.dll"
assert_file_kind "$host_unix_ntdll_path" "Mach-O 64-bit" \
  "host Unix ntdll.so"

assert_glob_match() {
  setopt local_options null_glob

  local description="$1"
  shift
  local matches=("$@")

  if (( ${#matches[@]} == 0 )); then
    echo "Missing $description." >&2
    exit 65
  fi
}

assert_dylib_install_name() {
  local dylib_path="$1"
  local expected_name="$2"
  local install_name

  install_name="$(otool -D "$dylib_path" | tail -n 1)"
  if [[ "$install_name" != "$expected_name" ]]; then
    echo "Unexpected install name for ${dylib_path#$runtime_root/}:" >&2
    echo "expected: $expected_name" >&2
    echo "actual:   $install_name" >&2
    exit 65
  fi
}

assert_macho_has_rpath() {
  local relative_path="$1"
  local expected_rpath="$2"
  local target_path="$runtime_root/$relative_path"

  if ! otool -l "$target_path" |
    awk '/LC_RPATH/ { getline; getline; print $2 }' |
    grep -Fx "$expected_rpath" >/dev/null; then
    echo "$relative_path is missing LC_RPATH $expected_rpath." >&2
    exit 65
  fi
}

assert_macho_exports_symbol() {
  local relative_path="$1"
  local expected_symbol="$2"
  local target_path="$runtime_root/$relative_path"

  if ! nm -gU "$target_path" | awk '{ print $NF }' | grep -Fx "$expected_symbol" >/dev/null; then
    echo "$relative_path does not export required symbol $expected_symbol." >&2
    exit 65
  fi
}

assert_macho_uses_dependency() {
  local relative_path="$1"
  local expected_dependency="$2"
  local target_path="$runtime_root/$relative_path"

  if ! otool -L "$target_path" | awk 'NR > 1 { print $1 }' |
    grep -Fx "$expected_dependency" >/dev/null; then
    echo "$relative_path does not use required dependency $expected_dependency." >&2
    exit 65
  fi
}

assert_macho_rejects_dependency() {
  local relative_path="$1"
  local rejected_dependency="$2"
  local target_path="$runtime_root/$relative_path"

  if otool -L "$target_path" | awk 'NR > 1 { print $1 }' |
    grep -Fx "$rejected_dependency" >/dev/null; then
    echo "$relative_path still uses rejected dependency $rejected_dependency." >&2
    exit 65
  fi
}

assert_runtime_dylib_glob() {
  setopt local_options null_glob

  local description="$1"
  local expected_glob="$2"
  local dylib_path
  local dylibs=("$runtime_root"/lib/${~expected_glob})

  assert_glob_match "$description" "${dylibs[@]}"
  for dylib_path in "${dylibs[@]}"; do
    assert_file_kind "${dylib_path#$runtime_root/}" "Mach-O 64-bit" "$description"
    assert_dylib_install_name "$dylib_path" "@rpath/$(basename "$dylib_path")"
    assert_macho_has_rpath "${dylib_path#$runtime_root/}" "@loader_path"
  done
}

assert_runtime_dylib_glob "GnuTLS runtime dylib" "libgnutls*.dylib"
assert_runtime_dylib_glob "libiconv runtime dylib" "libiconv*.dylib"
assert_runtime_dylib_glob "GSSAPI runtime dylib" "libgssapi_krb5*.dylib"
assert_runtime_dylib_glob "Kerberos runtime dylib" "libkrb5*.dylib"
assert_runtime_dylib_glob "OpenCL runtime dylib" "libOpenCL*.dylib"
assert_runtime_dylib_glob "libusb runtime dylib" "libusb-1.0*.dylib"
assert_macho_exports_symbol "lib/libiconv.2.dylib" "_libiconv"
assert_macho_exports_symbol "lib/libiconv-darwin.2.dylib" "_iconv"
assert_macho_uses_dependency "lib/libidn2.0.dylib" "@loader_path/libiconv.2.dylib"
assert_macho_uses_dependency "lib/libintl.8.dylib" "@loader_path/libiconv-darwin.2.dylib"
assert_macho_rejects_dependency "lib/libintl.8.dylib" "@loader_path/libiconv.2.dylib"

assert_macho_has_rpath "lib/wine/x86_64-unix/secur32.so" "@loader_path/../../"
assert_macho_has_rpath "lib/wine/x86_64-unix/bcrypt.so" "@loader_path/../../"
assert_macho_has_rpath "lib/wine/x86_64-unix/kerberos.so" "@loader_path/../../"
assert_macho_has_rpath "lib/wine/x86_64-unix/opencl.so" "@loader_path/../../"
assert_macho_has_rpath "lib/wine/x86_64-unix/wineusb.so" "@loader_path/../../"

find_macho_nix_references() {
  local scan_root
  local candidate_path
  local relative_path
  local file_output

  for scan_root in "$runtime_root/bin" "$runtime_root/lib"; do
    if [[ ! -d "$scan_root" ]]; then
      continue
    fi

    find "$scan_root" -type f -print |
      while IFS= read -r candidate_path; do
        file_output="$(/usr/bin/file "$candidate_path")"
        if [[ "$file_output" != *"Mach-O"* ]]; then
          continue
        fi

        relative_path="${candidate_path#$runtime_root/}"
        otool -L "$candidate_path" |
          awk -v relative_path="$relative_path" \
            'NR > 1 && $1 ~ /^\/nix\/store\/.*\.dylib$/ { print relative_path ": " $1 }'

        otool -l "$candidate_path" |
          awk -v relative_path="$relative_path" \
            '/LC_RPATH/ { getline; getline; if ($2 ~ /^\/nix\/store\//) print relative_path ": " $2 }'
      done
  done
}

nix_references="$(find_macho_nix_references)"
if [[ -n "$nix_references" ]]; then
  echo "Wine runtime Mach-O files must not reference unpackaged Nix store paths:" >&2
  echo "$nix_references" >&2
  exit 65
fi

echo "Wine32-on-64 runtime layout OK: $runtime_root"
