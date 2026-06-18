#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

usage() {
  cat >&2 <<'EOF'
Usage: smoke-gptk-d3dmetal-local.zsh [options] <runtime-root-or-stack-archive>

Runs the GPTK/D3DMetal D3D11 and D3D12 backend smoke tests against a temporary
copy of a Konyak macOS runtime. The input may be either an assembled runtime
root directory or konyak-macos-wine-runtime-stack.tar.zst.

Options:
  --work-root <dir>          Reuse this local work directory for the copied
                             runtime, downloaded Gcenx archive, extracted
                             payload, and probe executables.
  --allow-unsupported-host   Accept the exact hosted-runner D3DMetal
                             unsupported-GPU signature. Leave this unset for
                             local Apple Silicon device-creation proof.
  --keep-work-root           Keep the generated temporary work directory after
                             the smoke finishes. Ignored when --work-root is
                             supplied.
  -h, --help                 Show this help.

The pinned Gcenx GPTK/D3DMetal archive is downloaded only as a transient smoke
input. Do not upload the work directory or include it in Konyak release assets.
EOF
}

fail() {
  echo "$1" >&2
  exit "${2:-65}"
}

work_root=""
work_root_supplied=0
keep_work_root="${KONYAK_GPTK_D3DMETAL_LOCAL_KEEP_WORK_ROOT:-0}"
allow_unsupported_host="${KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST:-0}"
input_path=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --work-root)
      [[ "$#" -ge 2 ]] || fail "--work-root requires a directory path" 64
      work_root="$2"
      work_root_supplied=1
      shift 2
      ;;
    --allow-unsupported-host)
      allow_unsupported_host=1
      shift
      ;;
    --keep-work-root)
      keep_work_root=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "Unknown option: $1" 64
      ;;
    *)
      [[ -z "$input_path" ]] || fail "Only one runtime root or stack archive may be supplied" 64
      input_path="$1"
      shift
      ;;
  esac
done

if [[ "$#" -gt 0 ]]; then
  [[ -z "$input_path" ]] || fail "Only one runtime root or stack archive may be supplied" 64
  input_path="$1"
  shift
fi
[[ "$#" -eq 0 ]] || fail "Unexpected trailing arguments: $*" 64

if [[ -z "$input_path" ]]; then
  usage
  exit 64
fi

if [[ -z "$work_root" ]]; then
  work_root="$(mktemp -d "${TMPDIR:-/tmp}/konyak-gptk-d3dmetal-local-smoke.XXXXXXXXXX")"
fi

case "$work_root" in
  dist|dist/*|*/dist|*/dist/*)
    fail "Refusing to place transient GPTK/D3DMetal smoke payload under a dist/ directory: $work_root"
    ;;
esac

mkdir -p "$(dirname "$work_root")"
work_root="$(cd "$(dirname "$work_root")" && pwd -P)/$(basename "$work_root")"

case "$work_root" in
  */dist|*/dist/*)
    fail "Refusing to place transient GPTK/D3DMetal smoke payload under a dist/ directory: $work_root"
    ;;
esac

cleanup() {
  if [[ "$work_root_supplied" -eq 0 && "$keep_work_root" != 1 ]]; then
    rm -rf "$work_root"
  fi
}
trap cleanup EXIT

mkdir -p "$work_root"

if [[ -d "$input_path" ]]; then
  input_path="$(cd "$input_path" && pwd -P)"
  input_kind="directory"
elif [[ -f "$input_path" ]]; then
  input_path="$(cd "$(dirname "$input_path")" && pwd -P)/$(basename "$input_path")"
  input_kind="archive"
else
  fail "Runtime root or stack archive does not exist: $input_path" 66
fi

smoke_runtime_root="$work_root/runtime"
gptk_work_root="$work_root/gptk"
probe_root="$work_root/probes"

rm -rf "$smoke_runtime_root"
mkdir -p "$smoke_runtime_root"

case "$input_kind" in
  archive)
    "$repo_root/scripts/check-runtime-archive-excludes-gptk.zsh" "$input_path" >/dev/null
    tar --warning=no-unknown-keyword -xaf "$input_path" -C "$smoke_runtime_root"
    ;;
  directory)
    [[ -d "$input_path/lib/wine/x86_64-windows" ]] ||
      fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $input_path"
    [[ -d "$input_path/lib/wine/x86_64-unix" ]] ||
      fail "Runtime root does not look like a Konyak x86_64 Wine runtime: $input_path"
    rsync -a --delete "$input_path"/ "$smoke_runtime_root"/
    ;;
esac

"$repo_root/scripts/check-wine32on64-runtime.zsh" "$smoke_runtime_root" >/dev/null
"$repo_root/scripts/prepare-gptk-d3dmetal-ci-smoke.zsh" "$smoke_runtime_root" "$gptk_work_root"

if [[ "$allow_unsupported_host" == 1 ]]; then
  export KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST=1
else
  unset KONYAK_ALLOW_GPTK_UNSUPPORTED_HOST
fi

"$repo_root/scripts/smoke-backend-device.zsh" \
  "$smoke_runtime_root" \
  gptk-d3d11-device \
  "$probe_root"

"$repo_root/scripts/smoke-backend-device.zsh" \
  "$smoke_runtime_root" \
  gptk-d3d12-device \
  "$probe_root"

echo "GPTK/D3DMetal local smoke OK: $input_path"
