#!/usr/bin/env zsh
set -euo pipefail

runtime_root="${1:-}"

if [[ -z "$runtime_root" ]]; then
  echo "Usage: $0 <runtime-root>" >&2
  exit 64
fi

if [[ ! -d "$runtime_root" ]]; then
  echo "Runtime root does not exist: $runtime_root" >&2
  exit 65
fi

winetricks_path="$runtime_root/winetricks"
verbs_path="$runtime_root/verbs.txt"

if [[ ! -x "$winetricks_path" ]]; then
  echo "Winetricks executable is missing or not executable: $winetricks_path" >&2
  exit 65
fi

if [[ ! -s "$verbs_path" ]]; then
  echo "Winetricks verb catalog is missing or empty: $verbs_path" >&2
  exit 65
fi

if ! grep -Eq '^===== [^=]+ =====$' "$verbs_path"; then
  echo "Winetricks verb catalog does not contain category headers: $verbs_path" >&2
  exit 65
fi

if ! grep -Eq '^win10[[:space:]]+' "$verbs_path"; then
  echo "Winetricks verb catalog does not contain the win10 verb: $verbs_path" >&2
  exit 65
fi
