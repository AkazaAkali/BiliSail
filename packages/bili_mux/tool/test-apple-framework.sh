#!/usr/bin/env bash
# Exercise the production packaging step without Xcode or an FFmpeg build.
set -euo pipefail
package_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d -t bilisail-framework-test.XXXXXX)"
work="$(cd "$work" && pwd -P)"
trap 'rm -rf -- "$work"' EXIT
fixture="$work/package with spaces"
mkdir -p "$fixture/tool"
cp "$package_dir/tool/package-apple-framework.sh" "$fixture/tool/"

for platform in ios macos; do
  prebuilt="$fixture/native/prebuilt/$platform-arm64"
  mkdir -p "$prebuilt/BiliMux.framework"
  printf '%s binary\n' "$platform" > "$prebuilt/BiliMux.framework/BiliMux"
  info="$package_dir/native/Info.plist"
  if [[ "$platform" == ios ]]; then info="$package_dir/native/Info.ios.plist"; fi
  cp "$info" "$prebuilt/BiliMux.framework/Info.plist"
  for record in COPYING.LGPLv2.1 source.txt configure.log; do
    printf '%s %s\n' "$platform" "$record" > "$prebuilt/$record"
  done
  framework="$fixture/$platform/Frameworks/BiliMux.framework"
  # Reproduce the old output, then rebuild twice to cover retained build dirs.
  mkdir -p "$framework/Resources" "$framework/_CodeSignature"
  printf 'stale\n' > "$framework/Resources/configure.log"
  printf 'stale\n' > "$framework/_CodeSignature/CodeResources"
  for attempt in 1 2; do
    bash "$fixture/tool/package-apple-framework.sh" "$platform-arm64"
    cmp "$prebuilt/BiliMux.framework/BiliMux" "$framework/BiliMux"
    cmp "$info" "$framework/Info.plist"
    [[ ! -e "$framework/_CodeSignature" && ! -e "$framework/Versions" ]]
    resources="$framework/Resources"
    if [[ "$platform" == ios ]]; then
      [[ ! -e "$resources" ]]
      resources="$framework"
    fi
    for record in COPYING.LGPLv2.1 source.txt configure.log; do
      cmp "$prebuilt/$record" "$resources/$record"
    done
    [[ "$(find "$framework" -type f | wc -l | tr -d ' ')" == 5 ]]
  done
done
echo 'Apple framework packaging checks passed (iOS/macOS, rebuild twice).'
