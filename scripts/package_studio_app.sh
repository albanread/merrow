#!/bin/zsh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only supports macOS." >&2
  exit 1
fi

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
APP_NAME="Merrow Studio.app"
APP_SLUG="merrow-studio"
RELEASE_DIR="${REPO_ROOT}/release"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SOURCE_BINARY="${REPO_ROOT}/zig-out/bin/merrow-studio"
SOURCE_PLIST="${REPO_ROOT}/app/Info.plist"
SOURCE_FONTS_DIR="${REPO_ROOT}/fonts"
SOURCE_ICON_PNG="${REPO_ROOT}/app/assets/merrow-studio-icon.png"
VERSION_FILE="${REPO_ROOT}/build.zig.zon"
TARGET_BINARY="${MACOS_DIR}/merrow-studio"
TARGET_FONTS_DIR="${RESOURCES_DIR}/fonts"
TARGET_ICON_ICNS="${RESOURCES_DIR}/MerrowStudio.icns"

extract_app_version() {
  local version
  version=$(awk -F '"' '/\.version = / { print $2; exit }' "$VERSION_FILE")

  if [[ -z "$version" ]]; then
    echo "Unable to determine app version from ${VERSION_FILE}." >&2
    exit 1
  fi

  printf '%s' "$version"
}

generate_app_icon() {
  local source_png="$1"
  local target_icns="$2"
  local iconset_dir
  iconset_dir=$(mktemp -d)

  mkdir -p "${iconset_dir}/MerrowStudio.iconset"

  local -a sizes=(16 32 128 256 512)
  local size
  for size in "${sizes[@]}"; do
    /usr/bin/sips -z "$size" "$size" "$source_png" --out "${iconset_dir}/MerrowStudio.iconset/icon_${size}x${size}.png" >/dev/null

    local retina_size=$((size * 2))
    /usr/bin/sips -z "$retina_size" "$retina_size" "$source_png" --out "${iconset_dir}/MerrowStudio.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done

  /usr/bin/iconutil -c icns "${iconset_dir}/MerrowStudio.iconset" -o "$target_icns"
  rm -rf "$iconset_dir"
}

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

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "Missing version file at ${VERSION_FILE}." >&2
  exit 1
fi

APP_VERSION=$(extract_app_version)
ZIP_NAME="${APP_SLUG}-macos-${APP_VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$RELEASE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -f "$ZIP_PATH"

cp "$SOURCE_BINARY" "$TARGET_BINARY"
cp "$SOURCE_PLIST" "${CONTENTS_DIR}/Info.plist"
cp -R "$SOURCE_FONTS_DIR" "$TARGET_FONTS_DIR"

if [[ -f "$SOURCE_ICON_PNG" ]]; then
  generate_app_icon "$SOURCE_ICON_PNG" "$TARGET_ICON_ICNS"
else
  echo "Warning: no source app icon found at ${SOURCE_ICON_PNG}; packaging app without custom icon." >&2
fi

ln -s ../Resources/fonts "${MACOS_DIR}/fonts"
printf 'APPLMRRW' > "${CONTENTS_DIR}/PkgInfo"
chmod 755 "$TARGET_BINARY"

/usr/bin/plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Created ${APP_BUNDLE}"
echo "Created ${ZIP_PATH}"
