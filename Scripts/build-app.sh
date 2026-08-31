#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/.build/Glina.app"
INSTALLED=${GLINA_INSTALL_APP_PATH:-"$HOME/Applications/Glina.app"}
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCT_VERSION=${WISENT_RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")}
BUILD_NUMBER=${WISENT_BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}
case "$PRODUCT_VERSION" in
  *[!0-9.]*|'') printf 'Release version must use MAJOR.MINOR.PATCH syntax: %s\n' "$PRODUCT_VERSION" >&2; exit 1 ;;
esac
if [ "$(printf '%s' "$PRODUCT_VERSION" | awk -F. '{print NF}')" -ne 3 ]; then
  printf 'Release version must use MAJOR.MINOR.PATCH syntax: %s\n' "$PRODUCT_VERSION" >&2
  exit 1
fi
swift build --package-path "$ROOT" -c release --product GlinaDesktop
BIN_DIR=$(swift build --package-path "$ROOT" -c release --show-bin-path)
rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
install -m 0644 "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$PRODUCT_VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
# The feed URL already exists in this repository, in
# .wisent-desktop-release.json - the release manifest wisent-desktop-update
# reads. Until 2026-08-31 this script stamped SUFeedURL only from
# WISENT_UPDATE_FEED_URL, so every build that did not export that variable
# shipped the empty SUFeedURL that App/Info.plist carries: the installed 0.1.1
# bundle in ~/Applications has an empty SUFeedURL. Sparkle with no feed URL
# issues no request, so "Check for Updates…" did nothing at all.
#
# The manifest is now the default, the environment variable stays an override
# for a staging feed, and a bundle that would ship without a feed URL fails the
# build instead of being discovered months later by a user who never got an
# update.
RELEASE_MANIFEST="$ROOT/.wisent-desktop-release.json"
UPDATE_FEED_URL=${WISENT_UPDATE_FEED_URL:-}
if [ -z "$UPDATE_FEED_URL" ] && [ -f "$RELEASE_MANIFEST" ]; then
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required to read %s\n' "$RELEASE_MANIFEST" >&2
    exit 1
  }
  UPDATE_FEED_URL=$(jq -r '.feed_url // empty' "$RELEASE_MANIFEST")
fi
case "$UPDATE_FEED_URL" in
  https://*) ;;
  '')
    printf 'No update feed URL: set WISENT_UPDATE_FEED_URL, or .feed_url in %s. An app with an empty SUFeedURL can never check for updates.\n' "$RELEASE_MANIFEST" >&2
    exit 1 ;;
  *)
    printf 'Update feed must use HTTPS: %s\n' "$UPDATE_FEED_URL" >&2
    exit 1 ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
if [ -f "$ROOT/App/AppIcon.icns" ]; then
  install -m 0644 "$ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  sh "$ROOT/Scripts/import-brand-icon.sh" glina-desktop "$RESOURCES/AppIcon.icns"
fi
install -m 0755 "$BIN_DIR/GlinaDesktop" "$MACOS/GlinaDesktop"
for bundle in "$BIN_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  ditto "$bundle" "$RESOURCES/$(basename "$bundle")"
done
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
  ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
  if ! otool -l "$MACOS/GlinaDesktop" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS/GlinaDesktop"
  fi
fi

IDENTITY=${WISENT_CODESIGN_IDENTITY:-}
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application:/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/ {print $2; exit}')
fi
[ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ] || { echo 'Stable signing identity required' >&2; exit 1; }
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
  codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"
fi
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$MACOS/GlinaDesktop"
codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"

[ "${GLINA_INSTALL_AFTER_BUILD:-yes}" = no ] && exit 0
mkdir -p "$(dirname "$INSTALLED")"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
echo "Installed $INSTALLED"
