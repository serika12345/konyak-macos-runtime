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
prefix_init_executable="$runtime_root/lib/wine/x86_64-windows/cmd.exe"

required_paths=(
  "$wine_executable"
  "$wineserver_executable"
  "$prefix_init_executable"
  "$target_executable"
  "$runtime_root/lib/wine/i386-windows/kernel32.dll"
  "$runtime_root/lib/wine/i386-windows/ntdll.dll"
  "$runtime_root/lib/wine/x86_64-windows/kernel32.dll"
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
prefix_init_stdout_path="$work_root/prefix-init-stdout.log"
prefix_init_stderr_path="$work_root/prefix-init-stderr.log"
prefix_init_exit_status_path="$work_root/prefix-init-exit-status"
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

print_runtime_diagnostics() {
  echo "----- runtime diagnostics -----" >&2
  echo "runtime_root=$runtime_root" >&2
  echo "wine_executable=$wine_executable" >&2
  echo "prefix_init_executable=$prefix_init_executable" >&2
  echo "target_executable=$target_executable" >&2
  echo "WINEPREFIX=$WINEPREFIX" >&2
  echo "WINEDLLPATH=$WINEDLLPATH" >&2
  for diagnostic_path in \
    "$runtime_root/lib/wine/i386-windows/kernel32.dll" \
    "$runtime_root/lib/wine/i386-windows/ntdll.dll" \
    "$runtime_root/lib/wine/i386-windows/cmd.exe" \
    "$runtime_root/lib/wine/x86_64-windows/kernel32.dll" \
    "$runtime_root/lib/wine/x86_64-windows/ntdll.dll" \
    "$runtime_root/lib/wine/x86_64-windows/cmd.exe" \
    "$runtime_root/lib/wine/x86_64-windows/wow64.dll" \
    "$runtime_root/lib/wine/x86_64-windows/wow64cpu.dll" \
    "$runtime_root/lib/wine/x86_64-windows/wow64win.dll" \
    "$runtime_root/lib/wine/x86_64-unix/ntdll.so" \
    "$runtime_root/lib/wine/aarch64-unix/ntdll.so"
  do
    if [[ -e "$diagnostic_path" ]]; then
      /usr/bin/file "$diagnostic_path" >&2
    else
      echo "missing: $diagnostic_path" >&2
    fi
  done
  echo "----- end runtime diagnostics -----" >&2
}

run_wine_with_timeout() {
  local label="$1"
  local command_stdout_path="$2"
  local command_stderr_path="$3"
  local command_exit_status_path="$4"
  shift 4

  rm -f "$command_stdout_path" "$command_stderr_path" "$command_exit_status_path"
  (
    set +e
    "$@" >"$command_stdout_path" 2>"$command_stderr_path"
    echo "$?" >"$command_exit_status_path"
  ) &
  smoke_pid="$!"

  deadline=$((SECONDS + timeout_seconds))
  while [[ ! -f "$command_exit_status_path" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Wine32-on-64 $label timed out after ${timeout_seconds}s." >&2
      print_log_excerpt "stdout" "$command_stdout_path"
      print_log_excerpt "stderr" "$command_stderr_path"
      print_runtime_diagnostics
      exit 75
    fi
    sleep 1
  done

  wait "$smoke_pid" 2>/dev/null || true
  smoke_pid=""
  exit_code="$(cat "$command_exit_status_path")"

  if (( exit_code != 0 )); then
    echo "Wine32-on-64 $label exited with code $exit_code." >&2
    print_log_excerpt "stdout" "$command_stdout_path"
    print_log_excerpt "stderr" "$command_stderr_path"
    print_runtime_diagnostics
    exit 65
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
export GST_DEBUG="${GST_DEBUG:-1}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export WINEDATADIR="$runtime_root/share/wine"
export WINEDLLPATH="$runtime_root/lib/wine/x86_64-windows:$runtime_root/lib/wine/i386-windows:$runtime_root/lib/wine${WINEDLLPATH:+:$WINEDLLPATH}"
export DYLD_LIBRARY_PATH="$runtime_root/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
unset WINEDLLOVERRIDES
unset DYLD_FALLBACK_LIBRARY_PATH

run_wine_with_timeout \
  "prefix initialization" \
  "$prefix_init_stdout_path" \
  "$prefix_init_stderr_path" \
  "$prefix_init_exit_status_path" \
  "$wine_executable" "$prefix_init_executable" /c ver

"$wineserver_executable" -w >/dev/null 2>&1 || true

run_wine_with_timeout \
  "32-bit cmd launch smoke" \
  "$stdout_path" \
  "$stderr_path" \
  "$exit_status_path" \
  "$wine_executable" "$target_executable" /c echo "$sentinel"

if ! grep -F "$sentinel" "$stdout_path" >/dev/null; then
  echo "Wine32-on-64 launch smoke did not print the expected sentinel." >&2
  print_log_excerpt "stdout" "$stdout_path"
  print_log_excerpt "stderr" "$stderr_path"
  exit 65
fi

echo "Wine32-on-64 launch smoke OK: $runtime_root"
