#!/usr/bin/env bash
# Package an existing Ubuntu 24.04 x64 Flutter release bundle. No Flutter build
# runs here; build-release.ps1 supplies version, source archive and checksums.
set -euo pipefail
version="${1:?usage: package-linux.sh x.y.z+N output-directory}"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+(0|[1-9][0-9]*)$ ]] || { echo 'Invalid version' >&2; exit 1; }
[[ "$(uname -sm)" == 'Linux x86_64' ]] || { echo 'Linux x64 required' >&2; exit 1; }
if ! grep -Eq '^ID="?ubuntu"?$' /etc/os-release || ! grep -Eq '^VERSION_ID="?24\.04"?$' /etc/os-release; then
  echo 'Packaging requires the Ubuntu 24.04 baseline used by CI' >&2; exit 1
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
output="$(realpath "${2:?output-directory required}")"
work="$(dirname "$output")/linux-package-work"
[[ ! -e "$work" ]] || { echo "Staging already exists: $work" >&2; exit 1; }
mkdir -p "$work/tools" "$work/AppDir/usr/bin" "$work/AppDir/usr/share/doc/bilisail"
bundle="$repo/build/linux/x64/release/bundle"
for required in bilisail lib/libflutter_linux_gtk.so lib/libapp.so lib/libbili_mux.so data/icudtl.dat; do
  [[ -s "$bundle/$required" ]] || { echo "Missing bundle file: $required" >&2; exit 1; }
done
cp -a "$bundle/." "$work/AppDir/usr/bin/"
cp "$repo/THIRD_PARTY_NOTICES.md" "$work/AppDir/usr/share/doc/bilisail/"
cp "$repo/linux/packaging/AppRun" "$work/AppDir/AppRun"
cp "$repo/linux/packaging/flatpak-launcher" "$work/AppDir/"
chmod +x "$work/AppDir/AppRun" "$work/AppDir/flatpak-launcher"

download_verified() {
  local url="$1" sha="$2" destination="$3"
  curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 "$url" -o "$destination"
  echo "$sha  $destination" | sha256sum --check --status
}
# Pin both executable and GTK deployment hook; never execute a moving release.
download_verified \
  https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage \
  c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d \
  "$work/tools/linuxdeploy-x86_64.AppImage"
download_verified \
  https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/linuxdeploy-plugin-gtk.sh \
  b0f4cbc684a0103a9651f0955b635eaea0096b3a66c0f5a2c2aa337960375171 \
  "$work/tools/linuxdeploy-plugin-gtk.sh"
download_verified \
  https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/7a3fbc31a9e5075073ff8790f26effbac5f84453/LICENSE.txt \
  0718f6cadf38d2662f397591b777884c5389e65b9919aae6aca2bea87a52eac4 \
  "$work/tools/gtk-LICENSE.txt"
chmod +x "$work/tools/linuxdeploy-x86_64.AppImage" "$work/tools/linuxdeploy-plugin-gtk.sh"
gtk_notices="$work/AppDir/usr/share/doc/bilisail/linuxdeploy-gtk"
mkdir -p "$gtk_notices"
cp "$work/tools/gtk-LICENSE.txt" "$work/tools/linuxdeploy-plugin-gtk.sh" "$gtk_notices/"

export APPIMAGE_EXTRACT_AND_RUN=1 NO_STRIP=1 DEPLOY_GTK_VERSION=3
export LD_LIBRARY_PATH="$bundle/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# libmpv is dlopen'ed, so it must be explicitly added to dependency discovery.
mpv="$(pkg-config --variable=libdir mpv)/libmpv.so.2"
[[ -f "$mpv" ]] || { echo 'Install libmpv-dev' >&2; exit 1; }
"$work/tools/linuxdeploy-x86_64.AppImage" --appdir "$work/AppDir" \
  --executable "$work/AppDir/usr/bin/bilisail" --library "$mpv" \
  --desktop-file "$repo/linux/packaging/dev.bilisail.bilisail.desktop" \
  --icon-file "$repo/linux/packaging/dev.bilisail.bilisail.png" --plugin gtk

# Retain distro license texts and exact source/binary versions for every bundled
# distro library (the Flutter/mux licenses are supplied separately).
python3 "$repo/tool/linux-package-validation.py" "$work/AppDir" "$version"
export LDAI_OUTPUT="$output/BiliSail-$version-linux-x64.AppImage"
export LDAI_VERSION="$version"
# Reuse the type-2 runtime in our hash-verified linuxdeploy image. Otherwise
# appimagetool may download a moving runtime release while creating the image.
runtime_offset="$("$work/tools/linuxdeploy-x86_64.AppImage" --appimage-offset)"
[[ "$runtime_offset" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid AppImage runtime offset' >&2; exit 1; }
export LDAI_RUNTIME_FILE="$work/tools/appimage-runtime"
dd if="$work/tools/linuxdeploy-x86_64.AppImage" of="$LDAI_RUNTIME_FILE" bs=1 count="$runtime_offset" status=none
"$work/tools/linuxdeploy-x86_64.AppImage" --appdir "$work/AppDir" --output appimage
[[ -s "$LDAI_OUTPUT" ]] || { echo 'AppImage was not produced' >&2; exit 1; }

cp "$repo/linux/packaging/dev.bilisail.bilisail.json" "$work/manifest.json"
flatpak-builder --user --force-clean --disable-rofiles-fuse --repo="$work/repository" \
  "$work/flatpak-build" "$work/manifest.json"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$work/repository" "$output/BiliSail-$version-linux-x64.flatpak" dev.bilisail.bilisail
flatpak install --user --assumeyes --noninteractive --no-related \
  "$output/BiliSail-$version-linux-x64.flatpak"
# Check the actual exported package under the Runtime, where SDK-only libraries
# cannot accidentally hide a missing dependency. This does not launch the UI.
flatpak run --user --command=sh dev.bilisail.bilisail -ec '
  export LD_LIBRARY_PATH=/app/usr/bin/lib:/app/usr/lib
  find /app/usr -type f -name "*.so*" -exec sh -ec '\''
    for library do
      result=$(ldd "$library" 2>&1)
      if printf "%s\n" "$result" | grep -q "not found"; then
        printf "%s\n%s\n" "$library" "$result" >&2
        exit 1
      fi
    done
  '\'' sh {} +
  ldd /app/usr/bin/bilisail > /tmp/bilisail-ldd.txt
  ! grep -q "not found" /tmp/bilisail-ldd.txt
'
python3 - "$repo/linux/packaging/dev.bilisail.bilisail.json" "$(dirname "$output")/linux-packaging.json" <<'PY'
import json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps({
    "runtime": manifest["runtime"], "runtimeVersion": manifest["runtime-version"],
    "applicationId": manifest["app-id"], "hostBaseline": "Ubuntu 24.04 x64",
    "displayBackend": "X11 (XWayland on Wayland)",
    "dependencyValidation": "AppDir and installed Flatpak Runtime ldd",
    "linuxdeployVersion": "1-alpha-20251107-1",
}, indent=2) + "\n")
PY
