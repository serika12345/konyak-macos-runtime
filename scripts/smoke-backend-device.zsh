#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
runtime_root="${1:-}"
backend="${2:-}"
probe_dir="${3:-$repo_root/.dart_tool/backend-probes}"
timeout_seconds="${KONYAK_BACKEND_SMOKE_TIMEOUT_SECONDS:-180}"

if [[ -z "$runtime_root" || -z "$backend" ]]; then
  echo "Usage: $0 <assembled-runtime-root> <dxvk-d3d11|dxmt-d3d11|vkd3d-d3d12|gptk-d3d11-device|gptk-d3d12-device> [probe-dir]" >&2
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

typeset -a dll_path_entries
typeset -a dyld_path_entries
typeset -a dyld_framework_path_entries
typeset -a wine_path_entries
typeset -a wine_windows_paths
typeset -a required_paths
probe_name=""
probe_runtime_directory=""
probe_launch_path=""
success_marker=""
backend_overrides=""

case "$backend" in
  dxvk-d3d11)
    probe_name="d3d11_device_probe.exe"
    probe_runtime_directory="$runtime_root/lib/dxvk/x86_64-windows"
    success_marker="KONYAK_D3D11_DEVICE_PROBE_OK"
    backend_overrides="dxgi,d3d9,d3d10,d3d10_1,d3d10core,d3d11=n,b"
    dll_path_entries=(
      "$runtime_root/lib/dxvk/x86_64-windows"
      "$runtime_root/lib/dxvk/i386-windows"
    )
    required_paths=(
      "$runtime_root/lib/dxvk/x86_64-windows/dxgi.dll"
      "$runtime_root/lib/dxvk/x86_64-windows/d3d11.dll"
      "$runtime_root/lib/libMoltenVK.dylib"
    )
    ;;
  dxmt-d3d11)
    probe_name="d3d11_device_probe.exe"
    probe_runtime_directory="$runtime_root/lib/dxmt/x86_64-windows"
    success_marker="KONYAK_D3D11_DEVICE_PROBE_OK"
    backend_overrides="dxgi,d3d10core,d3d11,winemetal=n,b"
    dll_path_entries=(
      "$runtime_root/lib/dxmt/x86_64-windows"
      "$runtime_root/lib/dxmt/i386-windows"
    )
    dyld_path_entries=(
      "$runtime_root/lib/dxmt/x86_64-unix"
    )
    required_paths=(
      "$runtime_root/lib/dxmt/x86_64-windows/dxgi.dll"
      "$runtime_root/lib/dxmt/x86_64-windows/d3d11.dll"
      "$runtime_root/lib/dxmt/x86_64-windows/winemetal.dll"
      "$runtime_root/lib/dxmt/x86_64-windows/winemetal.so"
      "$runtime_root/lib/dxmt/x86_64-unix/winemetal.so"
      "$runtime_root/lib/libMoltenVK.dylib"
    )
    ;;
  vkd3d-d3d12)
    probe_name="d3d12_device_probe.exe"
    probe_runtime_directory="$runtime_root/lib/wine/x86_64-windows"
    success_marker="KONYAK_D3D12_DEVICE_PROBE_OK"
    backend_overrides="d3d12,d3d12core=n,b"
    dll_path_entries=()
    required_paths=(
      "$runtime_root/lib/wine/x86_64-windows/d3d12.dll"
      "$runtime_root/lib/wine/x86_64-windows/d3d12core.dll"
      "$runtime_root/lib/wine/x86_64-windows/libvkd3d-1.dll"
      "$runtime_root/lib/wine/x86_64-windows/libvkd3d-shader-1.dll"
      "$runtime_root/lib/wine/x86_64-windows/libvkd3d-utils-1.dll"
      "$runtime_root/lib/libMoltenVK.dylib"
    )
    ;;
  gptk-d3d11-device)
    probe_name="d3d11_device_probe.exe"
    probe_runtime_directory="$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows"
    success_marker="KONYAK_D3D11_DEVICE_PROBE_OK"
    backend_overrides="dxgi,d3d11,d3d12,nvapi64,nvngx=n,b"
    dll_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows"
    )
    dyld_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/external"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix"
    )
    dyld_framework_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/external"
    )
    required_paths=(
      "$runtime_root/lib/wine/x86_64-unix/cxcompatdb.so"
      "$runtime_root/components/gptk-d3dmetal/lib/external/D3DMetal.framework"
      "$runtime_root/components/gptk-d3dmetal/lib/external/libd3dshared.dylib"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/atidxx64.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d11.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d12.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/dxgi.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/nvapi64.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/nvngx.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/atidxx64.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d11.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d12.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/dxgi.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/nvapi64.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/nvngx.so"
    )
    ;;
  gptk-d3d12|gptk-d3d12-device)
    probe_name="d3d12_device_probe.exe"
    probe_runtime_directory="$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows"
    success_marker="KONYAK_D3D12_DEVICE_PROBE_OK"
    backend_overrides="dxgi,d3d11,d3d12,nvapi64,nvngx=n,b"
    dll_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows"
    )
    dyld_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/external"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix"
    )
    dyld_framework_path_entries=(
      "$runtime_root/components/gptk-d3dmetal/lib/external"
    )
    required_paths=(
      "$runtime_root/lib/wine/x86_64-unix/cxcompatdb.so"
      "$runtime_root/components/gptk-d3dmetal/lib/external/D3DMetal.framework"
      "$runtime_root/components/gptk-d3dmetal/lib/external/libd3dshared.dylib"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/atidxx64.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d11.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d12.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/dxgi.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/nvapi64.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/nvngx.dll"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/atidxx64.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d11.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d12.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/dxgi.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/nvapi64.so"
      "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/nvngx.so"
    )
    ;;
  *)
    echo "Unknown backend smoke target: $backend" >&2
    exit 64
    ;;
esac

required_paths=(
  "$wine_executable"
  "$wineserver_executable"
  "$prefix_init_executable"
  "$probe_runtime_directory"
  "$runtime_root/lib/wine/x86_64-windows/kernel32.dll"
  "$runtime_root/lib/wine/x86_64-windows/ntdll.dll"
  "$runtime_root/lib/wine/x86_64-unix/ntdll.so"
  "$runtime_root/lib/libfreetype.6.dylib"
  "$runtime_root/lib/libfreetype.dylib"
  "${required_paths[@]}"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Missing backend smoke prerequisite: $required_path" >&2
    exit 65
  fi
done

probe_path="$probe_dir/$probe_name"
if [[ ! -f "$probe_path" ]]; then
  "$repo_root/scripts/build-backend-probes.zsh" "$probe_dir" >/dev/null
fi
if [[ ! -f "$probe_path" ]]; then
  echo "Backend probe executable was not built: $probe_path" >&2
  exit 65
fi

probe_file_output="$(/usr/bin/file "$probe_path")"
if [[ "$probe_file_output" != *"PE32+ executable"* ]]; then
  echo "Backend probe is not an x86_64 Windows executable:" >&2
  echo "$probe_file_output" >&2
  exit 65
fi

work_root="$(mktemp -d "${TMPDIR:-/tmp}/konyak-${backend}-smoke.XXXXXXXXXX")"
prefix="$work_root/prefix"
stdout_path="$work_root/stdout.log"
stderr_path="$work_root/stderr.log"
exit_status_path="$work_root/exit-status"
prefix_init_stdout_path="$work_root/prefix-init-stdout.log"
prefix_init_stderr_path="$work_root/prefix-init-stderr.log"
prefix_init_exit_status_path="$work_root/prefix-init-exit-status"
registry_stdout_path="$work_root/registry-stdout.log"
registry_stderr_path="$work_root/registry-stderr.log"
registry_exit_status_path="$work_root/registry-exit-status"
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
  echo "----- backend smoke diagnostics -----" >&2
  echo "backend=$backend" >&2
  echo "runtime_root=$runtime_root" >&2
  echo "probe_path=$probe_path" >&2
  echo "probe_launch_path=$probe_launch_path" >&2
  echo "WINEPREFIX=$WINEPREFIX" >&2
  echo "WINEDATADIR=$WINEDATADIR" >&2
  echo "WINELOADER=$WINELOADER" >&2
  echo "WINESERVER=$WINESERVER" >&2
  echo "WINEDLLPATH=$WINEDLLPATH" >&2
  print -r -- "WINEPATH=${WINEPATH:-}" >&2
  echo "WINEDLLOVERRIDES=$WINEDLLOVERRIDES" >&2
  print -r -- "CX_APPLEGPTK_LIBD3DSHARED_PATH=${CX_APPLEGPTK_LIBD3DSHARED_PATH:-}" >&2
  echo "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH" >&2
  print -r -- "DYLD_FRAMEWORK_PATH=${DYLD_FRAMEWORK_PATH:-}" >&2
  for diagnostic_path in \
    "$probe_path" \
    "$runtime_root/lib/libMoltenVK.dylib" \
    "$runtime_root/lib/wine/x86_64-windows/d3d11.dll" \
    "$runtime_root/lib/wine/x86_64-windows/d3d12.dll" \
    "$runtime_root/lib/wine/x86_64-windows/dxgi.dll" \
    "$runtime_root/lib/dxvk/x86_64-windows/d3d11.dll" \
    "$runtime_root/lib/dxvk/x86_64-windows/dxgi.dll" \
    "$runtime_root/lib/dxmt/x86_64-windows/d3d11.dll" \
    "$runtime_root/lib/dxmt/x86_64-windows/dxgi.dll" \
    "$runtime_root/lib/dxmt/x86_64-windows/winemetal.dll" \
    "$runtime_root/lib/dxmt/x86_64-windows/winemetal.so" \
    "$runtime_root/lib/dxmt/x86_64-unix/winemetal.so" \
    "$runtime_root/lib/wine/x86_64-windows/libvkd3d-1.dll" \
    "$runtime_root/lib/wine/x86_64-unix/cxcompatdb.so" \
    "$runtime_root/components/gptk-d3dmetal/lib/external/libd3dshared.dylib" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d11.dll" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/d3d12.dll" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-windows/dxgi.dll" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d11.so" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/d3d12.so" \
    "$runtime_root/components/gptk-d3dmetal/lib/wine/x86_64-unix/dxgi.so"
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
  echo "----- end backend smoke diagnostics -----" >&2
}

log_contains() {
  local path="$1"
  local pattern="$2"

  [[ -s "$path" ]] && grep -F "$pattern" "$path" >/dev/null
}

is_allowed_gptk_unsupported_host() {
  local log_path

  [[ "$backend" == gptk-* ]] || return 1
  [[ "${KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST:-0}" == "1" ]] || return 1

  for log_path in "$stdout_path" "$stderr_path"; do
    if log_contains "$log_path" "GPU not supported: Apple Paravirtual device" &&
      log_contains "$log_path" "D3DM: D3DMetal requires Apple silicon and macOS 14.0 Sonoma or higher."; then
      return 0
    fi
  done

  return 1
}

accept_gptk_unsupported_host() {
  echo "Backend smoke $label reached the CI host's unsupported GPTK/D3DMetal GPU signature." >&2
  echo "Treating this as an unsupported-host pass because KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST=1." >&2
  print_log_excerpt "stdout" "$command_stdout_path"
  print_log_excerpt "stderr" "$command_stderr_path"
  exit 0
}

wine_windows_path() {
  local unix_path="$1"
  local windows_path

  windows_path="${unix_path//\//\\}"
  printf 'Z:%s\n' "$windows_path"
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
    if is_allowed_gptk_unsupported_host; then
      accept_gptk_unsupported_host
    fi
    if (( SECONDS >= deadline )); then
      echo "Backend smoke $label timed out after ${timeout_seconds}s." >&2
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
    echo "Backend smoke $label exited with code $exit_code." >&2
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
}

cleanup() {
  stop_smoke_processes
  if [[ -n "$probe_launch_path" && "$probe_launch_path" != "$probe_path" ]]; then
    rm -f "$probe_launch_path"
  fi
  rm -rf "$work_root"
}

trap cleanup EXIT INT TERM

probe_launch_path="$probe_runtime_directory/.konyak-$backend-$probe_name"
cp -f "$probe_path" "$probe_launch_path"
chmod u+rw,go+r "$probe_launch_path"

wine_dll_paths=(
  "${dll_path_entries[@]}"
  "$runtime_root/lib/wine/x86_64-windows"
  "$runtime_root/lib/wine/i386-windows"
  "$runtime_root/lib/wine"
)
wine_path_entries=(
  "${dll_path_entries[@]}"
)
wine_windows_paths=()
for wine_path_entry in "${wine_path_entries[@]}"; do
  wine_windows_paths+=("$(wine_windows_path "$wine_path_entry")")
done

export WINEPREFIX="$prefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="$backend_overrides"
export GST_DEBUG="${GST_DEBUG:-1}"
export GST_PLUGIN_SYSTEM_PATH="$runtime_root/lib/gstreamer-1.0"
export GST_PLUGIN_SCANNER="$runtime_root/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_REGISTRY="$work_root/gstreamer-registry.bin"
export WINEDATADIR="$runtime_root/share/wine"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-0}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-debug}"
export DXVK_LOG_PATH="$work_root"
export WINEDLLPATH="${(j/:/)wine_dll_paths}"
if (( ${#wine_windows_paths[@]} > 0 )); then
  export WINEPATH="${(j/;/)wine_windows_paths}"
else
  unset WINEPATH
fi
export WINELOADER="$wine_executable"
export WINESERVER="$wineserver_executable"
export DYLD_LIBRARY_PATH="${(j/:/)dyld_path_entries}${dyld_path_entries:+:}$runtime_root/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
if (( ${#dyld_framework_path_entries[@]} > 0 )); then
  export DYLD_FRAMEWORK_PATH="${(j/:/)dyld_framework_path_entries}${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
else
  unset DYLD_FRAMEWORK_PATH
fi
if [[ "$backend" == gptk-* ]]; then
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="$runtime_root/components/gptk-d3dmetal/lib/external/libd3dshared.dylib"
  export D3DM_SUPPORT_DXR="${D3DM_SUPPORT_DXR:-1}"
else
  unset CX_APPLEGPTK_LIBD3DSHARED_PATH
fi
unset DYLD_FALLBACK_LIBRARY_PATH

run_wine_with_timeout \
  "prefix initialization" \
  "$prefix_init_stdout_path" \
  "$prefix_init_stderr_path" \
  "$prefix_init_exit_status_path" \
  "$wine_executable" "$prefix_init_executable" /c ver

"$wineserver_executable" -w >/dev/null 2>&1 || true

run_wine_with_timeout \
  "mac graphics driver registry update" \
  "$registry_stdout_path" \
  "$registry_stderr_path" \
  "$registry_exit_status_path" \
  "$wine_executable" reg add 'HKCU\Software\Wine\Drivers' \
    /v Graphics /t REG_SZ /d mac /f

"$wineserver_executable" -w >/dev/null 2>&1 || true

run_wine_with_timeout \
  "$backend" \
  "$stdout_path" \
  "$stderr_path" \
  "$exit_status_path" \
  "$wine_executable" "$probe_launch_path"

if ! grep -F "$success_marker" "$stdout_path" >/dev/null; then
  echo "Backend smoke did not print the expected marker: $success_marker" >&2
  print_log_excerpt "stdout" "$stdout_path"
  print_log_excerpt "stderr" "$stderr_path"
  print_runtime_diagnostics
  exit 65
fi

echo "Backend smoke OK: $backend"
