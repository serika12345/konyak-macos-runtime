#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"

if [[ -z "$runtime_root" || ! -d "$runtime_root" ]]; then
  echo "Usage: $0 <runtime-root>" >&2
  exit 64
fi

hosted_directory_name="Konyak Wine Hosted Application"
expected_loader_bundle_identifier="app.konyak.Konyak.WineLoader"
expected_wineserver_bundle_identifier="app.konyak.Konyak.WineServer"
required_wine_entitlements=(
  "com.apple.security.cs.allow-unsigned-executable-memory"
  "com.apple.security.cs.disable-executable-page-protection"
  "com.apple.security.cs.disable-library-validation"
  "com.apple.security.device.audio-input"
  "com.apple.security.device.camera"
)

required_paths=(
  "bin/wine"
  "bin/wineloader"
  "bin/wineserver"
  "$hosted_directory_name/wine"
  "$hosted_directory_name/wineloader"
  "$hosted_directory_name/wineserver"
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

host_unix_loader_candidates=(
  "lib/wine/x86_64-unix/wine"
  "lib/wine/aarch64-unix/wine"
)

if [[ ! -L "$runtime_root/bin" ]]; then
  echo "runtime/bin must be a symlink to $hosted_directory_name." >&2
  exit 65
fi

bin_target="$(readlink "$runtime_root/bin")"
if [[ "$bin_target" != "$hosted_directory_name" ]]; then
  echo "runtime/bin points at an unexpected target." >&2
  echo "expected: $hosted_directory_name" >&2
  echo "actual:   $bin_target" >&2
  exit 65
fi

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

host_unix_ntdll_paths=()
for candidate_path in "${host_unix_ntdll_candidates[@]}"; do
  if [[ -e "$runtime_root/$candidate_path" ]]; then
    host_unix_ntdll_paths+=("$candidate_path")
  fi
done

if (( ${#host_unix_ntdll_paths[@]} == 0 )); then
  echo "Missing Wine32-on-64 host Unix ntdll path: ${host_unix_ntdll_candidates[*]}" >&2
  exit 65
fi

host_unix_loader_paths=()
for candidate_path in "${host_unix_loader_candidates[@]}"; do
  if [[ -e "$runtime_root/$candidate_path" ]]; then
    host_unix_loader_paths+=("$candidate_path")
  fi
done

if (( ${#host_unix_loader_paths[@]} == 0 )); then
  echo "Missing Wine32-on-64 host Unix loader path: ${host_unix_loader_candidates[*]}" >&2
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
for host_unix_ntdll_path in "${host_unix_ntdll_paths[@]}"; do
  assert_file_kind "$host_unix_ntdll_path" "Mach-O 64-bit" \
    "host Unix ntdll.so"
done
assert_file_kind "bin/wine" "Mach-O 64-bit" \
  "hosted Wine loader stub"
assert_file_kind "bin/wineloader" "Mach-O 64-bit" \
  "hosted Wine loader"
assert_file_kind "bin/wineserver" "Mach-O 64-bit" \
  "hosted Wine server"

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

assert_macho_uses_only_system_dependencies() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local unexpected_dependencies

  unexpected_dependencies="$(
    otool -L "$target_path" |
      awk '
        NR <= 1 { next }
        $1 == "/usr/lib/libSystem.B.dylib" { next }
        $1 ~ /^\/usr\/lib\// { next }
        $1 ~ /^\/System\/Library\// { next }
        { print $1 }
      '
  )"

  if [[ -n "$unexpected_dependencies" ]]; then
    echo "$relative_path must not depend on packaged or third-party dylibs." >&2
    echo "Wine can copy this loader to a temporary winetemp path where @loader_path no longer points at the runtime root." >&2
    echo "$unexpected_dependencies" >&2
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
assert_macho_exports_symbol "lib/libiconv.2.dylib" "_iconv"
assert_macho_exports_symbol "lib/libiconv-darwin.2.dylib" "_iconv"
assert_macho_exports_symbol "lib/libiconv-gnu.2.dylib" "_libiconv"
assert_macho_uses_dependency "lib/libidn2.0.dylib" "@loader_path/libiconv-gnu.2.dylib"
assert_macho_rejects_dependency "lib/libidn2.0.dylib" "@loader_path/libiconv.2.dylib"
assert_macho_uses_dependency "lib/libintl.8.dylib" "@loader_path/libiconv-darwin.2.dylib"
assert_macho_rejects_dependency "lib/libintl.8.dylib" "@loader_path/libiconv.2.dylib"

for host_unix_ntdll_path in "${host_unix_ntdll_paths[@]}"; do
  host_unix_dir="${host_unix_ntdll_path%/ntdll.so}"
  assert_macho_has_rpath "$host_unix_dir/secur32.so" "@loader_path/../../"
  assert_macho_has_rpath "$host_unix_dir/bcrypt.so" "@loader_path/../../"
  assert_macho_has_rpath "$host_unix_dir/kerberos.so" "@loader_path/../../"
  assert_macho_has_rpath "$host_unix_dir/opencl.so" "@loader_path/../../"
  assert_macho_has_rpath "$host_unix_dir/wineusb.so" "@loader_path/../../"
done
for host_unix_loader_path in "${host_unix_loader_paths[@]}"; do
  assert_macho_uses_only_system_dependencies "$host_unix_loader_path"
done
assert_macho_uses_only_system_dependencies "bin/wine"
assert_macho_uses_only_system_dependencies "bin/wineloader"

assert_macho_signed() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"

  if ! codesign --verify "$target_path" >/dev/null 2>&1; then
    echo "$relative_path is not signed or has an invalid signature." >&2
    exit 65
  fi
}

assert_macho_signature_identity() {
  local relative_path="$1"
  local expected_identifier="$2"
  local target_path="$runtime_root/$relative_path"
  local signature_details

  signature_details="$(codesign -dv "$target_path" 2>&1)"

  if [[ "$signature_details" != *"Identifier=$expected_identifier"* ]]; then
    echo "$relative_path has an unexpected code-signing identifier." >&2
    echo "expected: $expected_identifier" >&2
    echo "$signature_details" >&2
    exit 65
  fi

  if [[ "$signature_details" == *"linker-signed"* ]]; then
    echo "$relative_path must be explicitly signed, not linker-signed." >&2
    echo "$signature_details" >&2
    exit 65
  fi

  if ! grep -E 'flags=0x[0-9a-fA-F]+\([^)]*runtime[^)]*\)' <<<"$signature_details" >/dev/null; then
    echo "$relative_path is not signed with the hardened runtime option." >&2
    echo "$signature_details" >&2
    exit 65
  fi
}

assert_macho_entitlements() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local entitlements
  local entitlement_key

  entitlements="$(codesign -d --entitlements :- "$target_path" 2>/dev/null || true)"
  for entitlement_key in "${required_wine_entitlements[@]}"; do
    if [[ "$entitlements" != *"<key>$entitlement_key</key>"* ]]; then
      echo "$relative_path is missing required Wine entitlement: $entitlement_key" >&2
      echo "$entitlements" >&2
      exit 65
    fi
  done
}

assert_macho_bound_info_plist() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local signature_details

  signature_details="$(codesign -dv "$target_path" 2>&1)"
  if [[ "$signature_details" != *"Info.plist entries="* ]]; then
    echo "$relative_path must bind its embedded Info.plist into the code signature." >&2
    echo "$signature_details" >&2
    exit 65
  fi
}

assert_macho_embedded_info_plist_identity() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local embedded_strings

  embedded_strings="$(strings "$target_path")"
  if [[ "$embedded_strings" != *"$expected_loader_bundle_identifier"* ]]; then
    echo "$relative_path embedded Info.plist does not contain Konyak's Wine loader bundle identifier." >&2
    exit 65
  fi
  if [[ "$embedded_strings" != *"$hosted_directory_name"* ]]; then
    echo "$relative_path embedded Info.plist does not contain Konyak's hosted application name." >&2
    exit 65
  fi
  if [[ "$embedded_strings" != *"LSUIElement"* || "$embedded_strings" != *"<string>1</string>"* ]]; then
    echo "$relative_path embedded Info.plist does not keep CrossOver's LSUIElement startup policy." >&2
    exit 65
  fi
  if [[ "$embedded_strings" == *"com.codeweavers.CrossOver.wineloader"* ||
        "$embedded_strings" == *"CrossOver-Hosted Application"* ]]; then
    echo "$relative_path embedded Info.plist still contains CrossOver application identity." >&2
    exit 65
  fi
}

assert_no_crossover_identity_strings() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local embedded_strings

  embedded_strings="$(strings "$target_path")"
  if [[ "$embedded_strings" == *"com.codeweavers.CrossOver.wineloader"* ||
        "$embedded_strings" == *"CrossOver-Hosted Application"* ]]; then
    echo "$relative_path still contains CrossOver application identity strings." >&2
    exit 65
  fi
}

assert_no_winedllpath_temp_loader_rename() {
  local relative_path="$1"
  local target_path="$runtime_root/$relative_path"
  local embedded_strings

  embedded_strings="$(strings "$target_path")"
  if [[ "$embedded_strings" == *"winetemp-"* ||
        "$embedded_strings" == *"WINEPRELOADERAPPNAME"* ]]; then
    echo "$relative_path still contains CrossOver's WINEDLLPATH temp loader rename path." >&2
    exit 65
  fi
}

assert_macho_signed "bin/wineloader"
assert_macho_signed "bin/wine"
assert_macho_signed "bin/wineserver"
assert_macho_signature_identity "bin/wineloader" "$expected_loader_bundle_identifier"
assert_macho_signature_identity "bin/wine" "$expected_loader_bundle_identifier"
assert_macho_signature_identity "bin/wineserver" "$expected_wineserver_bundle_identifier"
assert_macho_entitlements "bin/wineloader"
assert_macho_entitlements "bin/wine"
assert_macho_entitlements "bin/wineserver"
assert_no_crossover_identity_strings "bin/wineloader"
assert_no_crossover_identity_strings "bin/wine"
assert_no_crossover_identity_strings "bin/wineserver"
assert_macho_bound_info_plist "bin/wineloader"
assert_macho_bound_info_plist "bin/wine"
assert_macho_embedded_info_plist_identity "bin/wineloader"
assert_macho_embedded_info_plist_identity "bin/wine"

for host_unix_loader_path in "${host_unix_loader_paths[@]}"; do
  assert_macho_signed "$host_unix_loader_path"
  assert_macho_signature_identity "$host_unix_loader_path" "$expected_loader_bundle_identifier"
  assert_macho_entitlements "$host_unix_loader_path"
  assert_no_crossover_identity_strings "$host_unix_loader_path"
  assert_macho_bound_info_plist "$host_unix_loader_path"
  assert_macho_embedded_info_plist_identity "$host_unix_loader_path"
done

for host_unix_ntdll_path in "${host_unix_ntdll_paths[@]}"; do
  assert_no_winedllpath_temp_loader_rename "$host_unix_ntdll_path"
done

find_macho_nix_references() {
  local scan_root
  local candidate_path
  local relative_path
  local file_output

  for scan_root in \
    "$runtime_root/$hosted_directory_name" \
    "$runtime_root/lib"; do
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
