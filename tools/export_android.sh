#!/usr/bin/env bash
# Builds a signed release APK (arm64) into dist/.
# Needs: Godot export templates of the engine version (android_release.apk in
# ~/.local/share/godot/export_templates/<ver>/), JDK 17+, Android SDK with
# build-tools (path in the Godot editor settings: export/android/android_sdk_path),
# and a release keystore passed through the standard Godot variables:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
#   tools/export_android.sh            -> dist/RealmOfLife-<version>.apk
cd "$(dirname "$0")/.."
set -e
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set the release keystore path}"
ver=$(grep -m1 '^version/name=' export_presets.cfg | cut -d'"' -f2)
mkdir -p dist
out="dist/RealmOfLife-${ver}.apk"
godot --headless --path . --export-release "Android" "$out"
rm -f "$out.idsig"
echo "built $out"
