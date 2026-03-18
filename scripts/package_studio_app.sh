#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only supports macOS." >&2
  exit 1
fi

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
APP_NAME="Merrow Studio.app"
APP_BUNDLE="${REPO_ROOT}/zig-out/${APP_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SOURCE_BINARY="${REPO_ROOT}/zig-out/bin/merrow-studio"
SOURCE_PLIST="${REPO_ROOT}/app/Info.plist"
SOURCE_FONTS_DIR="${REPO_ROOT}/fonts"
TARGET_BINARY="${MACOS_DIR}/merrow-studio"
TARGET_FONTS_DIR="${RESOURCES_DIR}/fonts"

pushd "$REPO_ROOT" >/dev/null
zig build "$@"
popd >/dev/null

if [[ ! -x "$SOURCE_BINARY" ]]; then
  echo "Expected studio binary at ${SOURCE_BINARY}, but it was not built." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_PLIST" ]]; then
  echo "Missing Info.plist template at ${SOURCE_PLIST}." >&2
  exit 1
fi

if [[ ! -d "$SOURCE_FONTS_DIR" ]]; then
  echo "Missing fonts directory at ${SOURCE_FONTS_DIR}." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$SOURCE_BINARY" "$TARGET_BINARY"
cp "$SOURCE_PLIST" "${CONTENTS_DIR}/Info.plist"
cp -R "$SOURCE_FONTS_DIR" "$TARGET_FONTS_DIR"
ln -s ../Resources/fonts "${MACOS_DIR}/fonts"
printf 'APPLMRRW' > "${CONTENTS_DIR}/PkgInfo"
chmod 755 "$TARGET_BINARY"

/usr/bin/plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

echo "Created ${APP_BUNDLE}"
