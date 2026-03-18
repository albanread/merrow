#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
APP_BUNDLE="${REPO_ROOT}/zig-out/Merrow Studio.app"
PACKAGE_SCRIPT="${SCRIPT_DIR}/package_studio_app.sh"

"$PACKAGE_SCRIPT"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle at ${APP_BUNDLE}, but it was not created." >&2
  exit 1
fi

exec /usr/bin/open -n "$APP_BUNDLE" --args "$@"
