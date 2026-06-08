#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"
timeout_seconds="${KONYAK_WINE32ON64_SMOKE_TIMEOUT_SECONDS:-300}"
sentinel="KONYAK_WINE32ON64_SMOKE_OK"

if [[ -z "$runtime_root" || ! -d "$runtime_root" ]]; then
  echo "Usage: $0 <assembled-runtime-root>" >&2
  exit 64
fi

runtime_root="$(cd "$runtime_root" && pwd -P)"
wine_executable="$runtime_root/bin/wine"
wineserver_executable="$runtime_root/bin/wineserver"
target_executable="$runtime_root/lib/wine/i386-windows/cmd.exe"

required_paths=(
  "$wine_executable"
  "$wineserver_executable"
  "$target_executable"
  "$runtime_root/lib/wine/i386-windows/ntdll.dll"
  "$runtime_root/lib/wine/x86_64-windows/wow64.dll"
  "$runtime_root/lib/wine/x86_64-windows/wow64cpu.dll"
  "$runtime_root/lib/wine/x86_64-windows/wow64win.dll"
  "$runtime_root/lib/libfreetype.6.dylib"
  "$runtime_root/lib/libfreetype.dylib"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing Wine32-on-64 smoke prerequisite: $required_path" >&2
    echo "Run this smoke test against an assembled Konyak runtime stack, not the Wine-only artifact." >&2
    exit 65
  fi
done

file_output="$(/usr/bin/file "$target_executable")"
if [[ "$file_output" != *"PE32 executable"* ]]; then
  echo "Wine32-on-64 smoke target is not a 32-bit Windows executable:" >&2
  echo "$file_output" >&2
  exit 65
fi

freetype_file_output="$(/usr/bin/file "$runtime_root/lib/libfreetype.6.dylib")"
if [[ "$freetype_file_output" != *"Mach-O 64-bit dynamically linked shared library x86_64"* ]]; then
  echo "Wine32-on-64 smoke FreeType dylib is not x86_64:" >&2
  echo "$freetype_file_output" >&2
  exit 65
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/konyak-wine32on64-smoke.XXXXXXXXXX")"
prefix="$work_root/prefix"
stdout_path="$work_root/stdout.log"
stderr_path="$work_root/stderr.log"
exit_status_path="$work_root/exit-status"
smoke_pid=""

print_log_excerpt() {
  local label="$1"
  local path="$2"

  if [[ -s "$path" ]]; then
    echo "----- $label -----" >&2
    /usr/bin/sed -n '1,160p' "$path" >&2
    echo "----- end $label -----" >&2
  fi
}

stop_smoke_processes() {
  if [[ -n "$smoke_pid" ]] && kill -0 "$smoke_pid" 2>/dev/null; then
    kill -TERM "$smoke_pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$smoke_pid" 2>/dev/null; then
      kill -KILL "$smoke_pid" 2>/dev/null || true
    fi
  fi

  WINEPREFIX="$prefix" \
  DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}" \
    "$wineserver_executable" -k >/dev/null 2>&1 || true

  /bin/ps -axo pid=,command= |
    /usr/bin/awk -v root="$work_root" 'index($0, root) > 0 { print $1 }' |
    while IFS= read -r wine_pid; do
      if [[ -n "$wine_pid" && "$wine_pid" != "$$" ]]; then
        kill -TERM "$wine_pid" 2>/dev/null || true
      fi
    done

  sleep 1

  /bin/ps -axo pid=,command= |
    /usr/bin/awk -v root="$work_root" 'index($0, root) > 0 { print $1 }' |
    while IFS= read -r wine_pid; do
      if [[ -n "$wine_pid" && "$wine_pid" != "$$" ]]; then
        kill -KILL "$wine_pid" 2>/dev/null || true
      fi
    done
}

cleanup() {
  stop_smoke_processes
  rm -rf "$work_root"
}

trap cleanup EXIT INT TERM

export WINEPREFIX="$prefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"
export GST_DEBUG="${GST_DEBUG:-1}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export WINEDLLPATH="$runtime_root/lib/wine/x86_64-windows:$runtime_root/lib/wine/i386-windows:$runtime_root/lib/wine${WINEDLLPATH:+:$WINEDLLPATH}"
export DYLD_LIBRARY_PATH="$runtime_root/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$runtime_root/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

(
  set +e
  "$wine_executable" "$target_executable" /c echo "$sentinel" >"$stdout_path" 2>"$stderr_path"
  echo "$?" >"$exit_status_path"
) &
smoke_pid="$!"

deadline=$((SECONDS + timeout_seconds))
while [[ ! -f "$exit_status_path" ]]; do
  if (( SECONDS >= deadline )); then
    echo "Wine32-on-64 launch smoke timed out after ${timeout_seconds}s." >&2
    print_log_excerpt "stdout" "$stdout_path"
    print_log_excerpt "stderr" "$stderr_path"
    exit 75
  fi
  sleep 1
done

wait "$smoke_pid" 2>/dev/null || true
exit_code="$(cat "$exit_status_path")"

if (( exit_code != 0 )); then
  echo "Wine32-on-64 launch smoke exited with code $exit_code." >&2
  print_log_excerpt "stdout" "$stdout_path"
  print_log_excerpt "stderr" "$stderr_path"
  exit 65
fi

if ! grep -F "$sentinel" "$stdout_path" >/dev/null; then
  echo "Wine32-on-64 launch smoke did not print the expected sentinel." >&2
  print_log_excerpt "stdout" "$stdout_path"
  print_log_excerpt "stderr" "$stderr_path"
  exit 65
fi

echo "Wine32-on-64 launch smoke OK: $runtime_root"
