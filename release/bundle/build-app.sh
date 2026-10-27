#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/.build/Glina.app"
# Where the operator launches the app from: ~/Applications unless
# GLINA_INSTALL_APP_PATH names another place.
if [ -n "${GLINA_INSTALL_APP_PATH+set}" ]; then
  INSTALLED=$GLINA_INSTALL_APP_PATH
else
  INSTALLED="$HOME/Applications/Glina.app"
fi
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Installed files: data readable by everyone and writable by its owner;
# executables additionally executable by everyone.
DATA_MODE=u=rw,go=r
EXECUTABLE_MODE=u=rwx,go=rx
# The version is the release's when it states one, else the one App/Info.plist
# declares; the build number is the release's, else the count of commits.
if [ -n "${WISENT_RELEASE_VERSION+set}" ]; then
  PRODUCT_VERSION=$WISENT_RELEASE_VERSION
else
  PRODUCT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")
fi
if [ -n "${WISENT_BUILD_NUMBER+set}" ]; then
  BUILD_NUMBER=$WISENT_BUILD_NUMBER
else
  BUILD_NUMBER=$(git -C "$ROOT" rev-list --count HEAD)
fi
# MAJOR.MINOR.PATCH: digits and dots only, three non-empty parts.
case "$PRODUCT_VERSION" in
  *[![:digit:].]*|''|.*|*.|*..*|*.*.*.*)
    printf 'Release version must use MAJOR.MINOR.PATCH syntax: %s\n' "$PRODUCT_VERSION" >&2
    false ;;
  *.*.*) ;;
  *)
    printf 'Release version must use MAJOR.MINOR.PATCH syntax: %s\n' "$PRODUCT_VERSION" >&2
    false ;;
esac
swift build --package-path "$ROOT" -c release --product GlinaDesktop
BIN_DIR=$(swift build --package-path "$ROOT" -c release --show-bin-path)
rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
install -m "$DATA_MODE" "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$PRODUCT_VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
# Stado resolves the deployment's update origin; source carries no host.
# WISENT_UPDATE_FEED_URL explicitly overrides it for a staging feed.
if [ -n "${WISENT_UPDATE_FEED_URL+set}" ]; then
  UPDATE_FEED_URL=$WISENT_UPDATE_FEED_URL
else
  UPDATE_FEED_URL=$(stado web origin url /api/release/appcast --query product=glina-desktop)
fi
case "$UPDATE_FEED_URL" in
  https://*) ;;
  '')
    printf '%s\n' "Stado returned no update feed URL; declare an appcast origin or set WISENT_UPDATE_FEED_URL." >&2
    false ;;
  *)
    printf 'Update feed must use HTTPS: %s\n' "$UPDATE_FEED_URL" >&2
    false ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
if [ -f "$ROOT/App/AppIcon.icns" ]; then
  install -m "$DATA_MODE" "$ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  sh "$ROOT/release/bundle/import-brand-icon.sh" glina-desktop "$RESOURCES/AppIcon.icns"
fi
install -m "$EXECUTABLE_MODE" "$BIN_DIR/GlinaDesktop" "$MACOS/GlinaDesktop"
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

# The shared signer signs the bundle with the hardened runtime and verifies
# continuity with the installed one. A release names its certificate in
# WISENT_CODESIGN_IDENTITY; otherwise Stado selects the declared Skarbiec
# certificate itself, so no identity is guessed from the login keychain.
if [ -n "${WISENT_CODESIGN_IDENTITY+set}" ]; then
  stado product signing sign "$APP" --identifier ai.wisent.glina.desktop \
    --previous "$INSTALLED" --identity "$WISENT_CODESIGN_IDENTITY" --hardened-runtime --json
else
  stado product signing sign "$APP" --identifier ai.wisent.glina.desktop \
    --previous "$INSTALLED" --hardened-runtime --json
fi
codesign --verify --strict --deep "$APP"
echo "Built $APP"

# The build installs unless GLINA_INSTALL_AFTER_BUILD says no.
if [ -n "${GLINA_INSTALL_AFTER_BUILD+set}" ] && [ "$GLINA_INSTALL_AFTER_BUILD" = no ]; then
  exit
fi
mkdir -p "$(dirname "$INSTALLED")"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
# While the .build copy stays registered it competes for Glina's URL schemes
# with the installed copy, so it is unregistered. `lsregister -u` also exits
# non-zero over the Spotlight importer's own failure to scan the .build copy,
# after the installed copy is already in place; that failure is said, with
# lsregister's own output left visible above, and the installed copy is still
# registered and restarted.
if ! "$LSREGISTER" -u "$APP"; then
  printf '%s\n' "lsregister did not unregister $APP (its output above says why); registering the installed copy anyway." >&2
fi
"$LSREGISTER" -f "$INSTALLED"
echo "Installed $INSTALLED"
# An install that does not restart is a silent no-op for anyone already running
# the app: the bundle on disk is new, the process in front of the operator is
# the old binary. Stado owns the restart: `--if-running` leaves a stopped app
# stopped and reports what LaunchServices observed.
stado product restart --if-running "$INSTALLED"
