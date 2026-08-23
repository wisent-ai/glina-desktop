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
swift build --package-path "$ROOT" -c release --product GlinaDesktop
BIN_DIR=$(swift build --package-path "$ROOT" -c release --show-bin-path)
rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
install -m 0644 "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
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
