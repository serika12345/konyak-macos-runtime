#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
derivation_path="${1:-$repo_root/nix/wine-crossover.nix}"

if [[ ! -f "$derivation_path" ]]; then
  echo "Wine derivation does not exist: $derivation_path" >&2
  exit 64
fi

required_flags=(
  "--enable-archs=i386,x86_64"
  "--disable-tests"
  "--without-x"
  "--with-coreaudio"
  "--with-cups"
  "--with-ffmpeg"
  "--with-freetype"
  "--with-gettext"
  "--with-gnutls"
  "--with-gssapi"
  "--with-gstreamer"
  "--with-inotify"
  "--with-krb5"
  "--with-mingw"
  "--with-opencl"
  "--with-pcap"
  "--with-pthread"
  "--with-sdl"
  "--with-unwind"
  "--with-usb"
  "--with-vulkan"
)

flags="$(
  awk '
    /configureFlags = \[/ { in_flags = 1; next }
    in_flags && /\];/ { exit }
    in_flags && $0 ~ /^[[:space:]]*"--/ {
      line = $0
      sub(/^[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
    }
  ' "$derivation_path"
)"

missing_flags=()
for required_flag in "${required_flags[@]}"; do
  if ! grep -Fxq -- "$required_flag" <<<"$flags"; then
    missing_flags+=("$required_flag")
  fi
done

if (( ${#missing_flags[@]} > 0 )); then
  echo "Wine configureFlags are missing required compatibility flags:" >&2
  printf '  %s\n' "${missing_flags[@]}" >&2
  exit 65
fi

disallowed_without_flags="$(
  grep -E '^--without-' <<<"$flags" | grep -Fvx -- "--without-x" || true
)"
if [[ -n "$disallowed_without_flags" ]]; then
  echo "Wine configureFlags contain disallowed --without-* flags:" >&2
  sed 's/^/  /' <<<"$disallowed_without_flags" >&2
  exit 65
fi

disallowed_disable_flags="$(
  grep -E '^--disable-' <<<"$flags" | grep -Fvx -- "--disable-tests" || true
)"
if [[ -n "$disallowed_disable_flags" ]]; then
  echo "Wine configureFlags contain disallowed --disable-* flags:" >&2
  sed 's/^/  /' <<<"$disallowed_disable_flags" >&2
  exit 65
fi

disallowed_forced_flags="$(
  grep -Fx -- "--with-opengl" <<<"$flags" || true
)"
if [[ -n "$disallowed_forced_flags" ]]; then
  echo "Wine configureFlags contain forced flags that break the Darwin baseline:" >&2
  sed 's/^/  /' <<<"$disallowed_forced_flags" >&2
  echo "  Darwin Wine should not force OpenGL because Wine 11 requires EGL when this flag is explicit." >&2
  exit 65
fi

echo "Wine configure flags OK: $derivation_path"
