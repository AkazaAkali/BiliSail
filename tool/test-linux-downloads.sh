#!/usr/bin/env bash
# Real curl/hash/cache behavior with local files; no network or account required.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo/tool/linux-downloads.sh"
work="$(mktemp -d -t bilisail-download-test.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
export BILISAIL_LINUX_CACHE="$work/cache"
printf 'verified tool\n' > "$work/source"
sha="$(sha256sum "$work/source" | cut -d ' ' -f 1)"

download_verified "file://$work/source" "$sha" "$work/first"
cmp "$work/source" "$work/first"
rm "$work/source"
download_verified "file://$work/source" "$sha" "$work/hit"
cmp "$work/first" "$work/hit"

# A corrupt cache entry must be downloaded again, never executed or copied out.
printf 'corrupt\n' > "$work/cache/tools/$sha"
cp "$work/first" "$work/source"
download_verified "file://$work/source" "$sha" "$work/repaired"
cmp "$work/first" "$work/repaired"

# A bad download must fail, leave no published cache entry and clean its temp.
bad_sha="$(printf 'different content' | sha256sum | cut -d ' ' -f 1)"
if download_verified "file://$work/source" "$bad_sha" "$work/rejected"; then
  echo 'Invalid download was accepted' >&2
  exit 1
fi
[[ ! -e "$work/rejected" && ! -e "$work/cache/tools/$bad_sha" ]]
[[ -z "$(find "$work/cache/tools" -name '.download.*' -print -quit)" ]]
echo 'Linux verified-download cache checks passed (4 cases).'
