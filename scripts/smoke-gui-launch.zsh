#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
runtime_root="${1:-}"
probe_dir="${2:-$repo_root/.dart_tool/backend-probes}"
timeout_seconds="${KONYAK_GUI_LAUNCH_SMOKE_TIMEOUT_SECONDS:-180}"
sentinel="KONYAK_GUI_LAUNCH_SMOKE_OK"

if [[ -z "$runtime_root" ]]; then
  echo "Usage: $0 <assembled-runtime-root> [probe-dir]" >&2
  exit 64
fi

if [[ ! -d "$runtime_root" ]]; then
  echo "Runtime root does not exist: $runtime_root" >&2
  exit 65
fi

runtime_root="$(cd "$runtime_root" && pwd -P)"
wine_executable="$runtime_root/bin/wineloader"
wineserver_executable="$runtime_root/bin/wineserver"
prefix_init_executable="$runtime_root/lib/wine/x86_64-windows/cmd.exe"
probe_path="$probe_dir/gui_launch_probe.exe"

required_paths=(
  "$wine_executable"
  "$wineserver_executable"
  "$prefix_init_executable"
  "$runtime_root/lib/wine/x86_64-windows/kernel32.dll"
  "$runtime_root/lib/wine/x86_64-windows/user32.dll"
  "$runtime_root/lib/wine/x86_64-windows/ntdll.dll"
  "$runtime_root/lib/wine/x86_64-unix/ntdll.so"
  "$runtime_root/lib/libfreetype.6.dylib"
  "$runtime_root/lib/libfreetype.dylib"
  "$runtime_root/lib/gstreamer-1.0"
  "$runtime_root/libexec/gstreamer-1.0/gst-plugin-scanner"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing GUI launch smoke prerequisite: $required_path" >&2
    exit 65
  fi
done

if [[ ! -f "$probe_path" ]]; then
  "$repo_root/scripts/build-backend-probes.zsh" "$probe_dir" >/dev/null
fi
if [[ ! -f "$probe_path" ]]; then
  echo "GUI launch probe executable was not built: $probe_path" >&2
  exit 65
fi

probe_file_output="$(/usr/bin/file "$probe_path")"
if [[ "$probe_file_output" != *"PE32+ executable"* ]]; then
  echo "GUI launch probe is not an x86_64 Windows executable:" >&2
  echo "$probe_file_output" >&2
  exit 65
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/konyak-gui-launch-smoke.XXXXXXXXXX")"
prefix="$work_root/prefix"
stdout_path="$work_root/stdout.log"
stderr_path="$work_root/stderr.log"
exit_status_path="$work_root/exit-status"
prefix_init_stdout_path="$work_root/prefix-init-stdout.log"
prefix_init_stderr_path="$work_root/prefix-init-stderr.log"
prefix_init_exit_status_path="$work_root/prefix-init-exit-status"
sentinel_path="$prefix/drive_c/konyak-gui-launch-smoke-ok.txt"
smoke_pid=""

print_log_excerpt() {
  local label="$1"
  local path="$2"

  if [[ -s "$path" ]]; then
    echo "----- $label -----" >&2
    /usr/bin/sed -n '1,200p' "$path" >&2
    echo "----- end $label -----" >&2
  fi
}

print_runtime_diagnostics() {
  echo "----- GUI launch smoke diagnostics -----" >&2
  echo "runtime_root=$runtime_root" >&2
  echo "probe_path=$probe_path" >&2
  echo "WINEPREFIX=$WINEPREFIX" >&2
  echo "WINELOADER=$WINELOADER" >&2
  echo "WINESERVER=$WINESERVER" >&2
  echo "WINEDLLPATH=$WINEDLLPATH" >&2
  echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH" >&2
  echo "DYLD_FALLBACK_LIBRARY_PATH=${DYLD_FALLBACK_LIBRARY_PATH:-}" >&2
  for diagnostic_path in \
    "$probe_path" \
    "$runtime_root/bin/wineloader" \
    "$runtime_root/bin/wine" \
    "$runtime_root/lib/wine/x86_64-windows/cmd.exe" \
    "$runtime_root/lib/wine/x86_64-windows/kernel32.dll" \
    "$runtime_root/lib/wine/x86_64-windows/user32.dll" \
    "$runtime_root/lib/wine/x86_64-unix/ntdll.so" \
    "$runtime_root/lib/libgnutls.30.dylib" \
    "$runtime_root/lib/libfreetype.6.dylib" \
    "$sentinel_path"
  do
    if [[ -e "$diagnostic_path" ]]; then
      /usr/bin/file "$diagnostic_path" >&2
    else
      echo "missing: $diagnostic_path" >&2
    fi
  done
  find "$work_root" -maxdepth 1 -type f -name "*.log" -print |
    sort |
    while IFS= read -r log_path; do
      print_log_excerpt "${log_path:t}" "$log_path"
    done
  echo "----- end GUI launch smoke diagnostics -----" >&2
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
      echo "GUI launch smoke $label timed out after ${timeout_seconds}s." >&2
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
    echo "GUI launch smoke $label exited with code $exit_code." >&2
    print_log_excerpt "stdout" "$command_stdout_path"
    print_log_excerpt "stderr" "$command_stderr_path"
    print_runtime_diagnostics
    exit 65
  fi
}

launch_wine_smoke() {
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
}

wait_for_smoke_exit() {
  local label="$1"
  local command_stdout_path="$2"
  local command_stderr_path="$3"
  local command_exit_status_path="$4"
  local exit_code

  if [[ -n "$smoke_pid" ]]; then
    wait "$smoke_pid" 2>/dev/null || true
    smoke_pid=""
  fi

  if [[ ! -f "$command_exit_status_path" ]]; then
    echo "GUI launch smoke $label did not record an exit status." >&2
    print_runtime_diagnostics
    exit 75
  fi

  exit_code="$(cat "$command_exit_status_path")"
  if (( exit_code != 0 )); then
    echo "GUI launch smoke $label exited with code $exit_code." >&2
    print_log_excerpt "stdout" "$command_stdout_path"
    print_log_excerpt "stderr" "$command_stderr_path"
    print_runtime_diagnostics
    exit 65
  fi
}

wait_for_sentinel() {
  local deadline
  deadline=$((SECONDS + timeout_seconds))
  while [[ ! -f "$sentinel_path" ]]; do
    if (( SECONDS >= deadline )); then
      echo "GUI launch smoke did not create sentinel after ${timeout_seconds}s." >&2
      print_runtime_diagnostics
      exit 75
    fi
    sleep 1
  done

  if ! grep -F "$sentinel" "$sentinel_path" >/dev/null; then
    echo "GUI launch smoke sentinel did not contain expected marker." >&2
    print_runtime_diagnostics
    exit 65
  fi
}

wait_for_active_wine_window() {
  local expected_title="$1"
  local deadline
  local front_pid

  deadline=$((SECONDS + timeout_seconds))
  while true; do
    front_pid="$(/usr/bin/osascript - "$expected_title" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set expectedTitle to item 1 of argv
  tell application "System Events"
    set candidateProcess to first process whose frontmost is true
    if name of candidateProcess is not "wine" then error "Wine is not frontmost"
    return unix id of candidateProcess
  end tell
end run
APPLESCRIPT
)"
    if [[ -n "$front_pid" ]]; then
      return
    fi

    if (( SECONDS >= deadline )); then
      echo "GUI launch smoke window did not become active/frontmost after ${timeout_seconds}s." >&2
      print_runtime_diagnostics
      exit 75
    fi
    sleep 1
  done
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
}

cleanup() {
  stop_smoke_processes
  rm -rf "$work_root"
}

trap cleanup EXIT INT TERM

wine_dll_paths=(
  "$runtime_root/lib/wine/x86_64-windows"
  "$runtime_root/lib/wine/i386-windows"
  "$runtime_root/lib/wine"
)

export WINEPREFIX="$prefix"
export WINEARCH=win64
export WINEDEBUG="fixme-all"
export GST_DEBUG="1"
export GST_PLUGIN_SYSTEM_PATH="$runtime_root/lib/gstreamer-1.0"
export GST_PLUGIN_SCANNER="$runtime_root/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_REGISTRY="$work_root/gstreamer-registry.bin"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export WINEDATADIR="$runtime_root/share/wine"
export WINEDLLPATH="${(j/:/)wine_dll_paths}"
export WINELOADER="$wine_executable"
export WINESERVER="$wineserver_executable"
export DYLD_LIBRARY_PATH="$runtime_root/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export KONYAK_GUI_LAUNCH_PROBE_HOLD_MS=8000
unset WINEDLLOVERRIDES
unset DYLD_FALLBACK_LIBRARY_PATH

run_wine_with_timeout \
  "prefix initialization" \
  "$prefix_init_stdout_path" \
  "$prefix_init_stderr_path" \
  "$prefix_init_exit_status_path" \
  "$wine_executable" wineboot --init

"$wineserver_executable" -w >/dev/null 2>&1 || true

launch_wine_smoke \
  "start /unix GUI launch" \
  "$stdout_path" \
  "$stderr_path" \
  "$exit_status_path" \
  "$wine_executable" start /unix "$probe_path"

wait_for_sentinel
wait_for_active_wine_window "Konyak GUI Launch Probe"
wait_for_smoke_exit \
  "start /unix GUI launch" \
  "$stdout_path" \
  "$stderr_path" \
  "$exit_status_path"
"$wineserver_executable" -w >/dev/null 2>&1 || true

echo "GUI launch smoke OK: $runtime_root"
