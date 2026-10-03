#!/bin/sh
# Stado's release pipeline runs this on the darwin builder: the same bundle
# build-app.sh makes for the operator, signed with the Developer ID identity
# the manifest's secret_env hands in, then copied to $WISENT_OUTPUT_DIR, where
# the manifest's stage map reads it. GLINA_INSTALL_AFTER_BUILD=no ends
# build-app.sh before it installs or restarts anything on the builder.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${WISENT_VERSION:?WISENT_VERSION is required}"
: "${WISENT_OUTPUT_DIR:?WISENT_OUTPUT_DIR is required}"
: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY is required}"

# The worker builds an unpacked git archive, so build-app.sh cannot count
# commits; the build number is derived from the version instead, which keeps
# it increasing with every release (MAJOR*10000 + MINOR*100 + PATCH).
major=${WISENT_VERSION%%.*}
rest=${WISENT_VERSION#*.}
minor=${rest%%.*}
patch=${rest#*.}
build_number=$((major * 10000 + minor * 100 + patch))

WISENT_RELEASE_VERSION="$WISENT_VERSION" \
WISENT_BUILD_NUMBER="$build_number" \
WISENT_CODESIGN_IDENTITY="$MACOS_SIGN_IDENTITY" \
GLINA_INSTALL_AFTER_BUILD=no \
  sh "$ROOT/release/bundle/build-app.sh"

rm -rf "$WISENT_OUTPUT_DIR/Glina.app"
ditto "$ROOT/.build/Glina.app" "$WISENT_OUTPUT_DIR/Glina.app"
