#!/usr/bin/env bash
# Vendor the LinkSense iOS SDK sources into the plugin target at a pinned tag.
#
# The SDK compiles inside the plugin's own `linksense` module, for both
# SwiftPM and CocoaPods hosts. A separate SDK package would add a `LinkSense`
# module whose generated module map differs from the plugin's `linksense` only
# by case, and on a case-insensitive disk one overwrites the other.
#
# The SDK's privacy manifest becomes the plugin's (the plugin itself collects
# nothing more), so the app ships exactly one, correct, manifest.
#
# Usage: ios/sync-ios-sdk.sh [tag]   (default: the pinned IOS_SDK_TAG below)
# Commit the result. Bump IOS_SDK_TAG together with the Android dependency in
# android/build.gradle so both platforms ship the same SDK version.
set -euo pipefail

IOS_SDK_TAG="${1:-v0.2.0}"
REPO="https://github.com/LinkSense-net/linksense-ios-sdk.git"
TARGET="$(cd "$(dirname "$0")" && pwd)/linksense/Sources/linksense"
DEST="$TARGET/LinkSenseCore"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$IOS_SDK_TAG" "$REPO" "$tmp/sdk"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$tmp/sdk/Sources/LinkSense/." "$DEST/"
mv "$DEST/Resources/PrivacyInfo.xcprivacy" "$TARGET/Resources/PrivacyInfo.xcprivacy"
rm -rf "$DEST/Resources"
echo "$IOS_SDK_TAG $(git -C "$tmp/sdk" rev-parse HEAD)" > "$DEST/VERSION"

echo "Vendored LinkSense iOS SDK $IOS_SDK_TAG into ios/linksense/Sources/linksense/LinkSenseCore/"
