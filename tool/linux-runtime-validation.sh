#!/bin/sh
# Run inside the installed Flatpak Runtime, not the SDK or host.
set -eu
root=${1:-/app}
export LC_ALL=C
export LD_LIBRARY_PATH="$root/usr/bin/lib:$root/usr/lib"
[ -f "$root/usr/bin/bilisail" ] || {
  echo "Missing executable: $root/usr/bin/bilisail" >&2
  exit 1
}
find "$root/usr" -type f \( -name '*.so*' -o -path "$root/usr/bin/bilisail" \) \
  -exec sh -c '
    failed=0
    for binary do
      status=0
      result=$(ldd "$binary" 2>&1) || status=$?
      if [ "$status" -ne 0 ] || printf "%s\n" "$result" | grep -q "not found"; then
        printf "Dependency check failed: %s (ldd exit %s)\n%s\n" \
          "$binary" "$status" "$result" >&2
        failed=1
      fi
    done
    exit "$failed"
  ' sh {} +
echo 'Installed Flatpak Runtime dependency checks passed.'
