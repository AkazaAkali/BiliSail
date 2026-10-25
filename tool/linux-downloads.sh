#!/usr/bin/env bash
# Cache only pinned download bytes; validate both restored and fresh entries.
download_verified() (
  set -euo pipefail
  local url="$1" sha="$2" destination="$3" cache_root cached temporary
  cache_root="${BILISAIL_LINUX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bilisail/linux}"
  mkdir -p "$cache_root/tools"
  cached="$cache_root/tools/$sha"
  if [[ ! -f "$cached" ]] || ! printf '%s  %s\n' "$sha" "$cached" | sha256sum --check --status; then
    temporary="$(mktemp "$cache_root/tools/.download.XXXXXX")"
    trap 'rm -f -- "$temporary"' EXIT
    curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 "$url" -o "$temporary" || return
    if ! printf '%s  %s\n' "$sha" "$temporary" | sha256sum --check --status; then
      echo 'Linux packaging tool SHA-256 mismatch' >&2
      return 1
    fi
    mv -f -- "$temporary" "$cached"
  fi
  cp -- "$cached" "$destination"
)

prepare_linux_packaging_tools() {
  local destination="$1"
  mkdir -p "$destination"
  download_verified \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage \
    c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d \
    "$destination/linuxdeploy-x86_64.AppImage" || return
  download_verified \
    https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh \
    b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171 \
    "$destination/linuxdeploy-plugin-gtk.sh" || return
  download_verified \
    https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/LICENSE.txt \
    0718f6cadf38d2662f397591b777884c5389e65b9919aae6aca2bea87a52eac4 \
    "$destination/gtk-LICENSE.txt" || return
  chmod +x "$destination/linuxdeploy-x86_64.AppImage" "$destination/linuxdeploy-plugin-gtk.sh"
}
