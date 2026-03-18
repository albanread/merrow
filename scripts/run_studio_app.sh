#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
APP_BUNDLE="${REPO_ROOT}/zig-out/Merrow Studio.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Studio app bundle not found at ${APP_BUNDLE}. Run scripts/build_and_run_studio_app.sh first." >&2
  exit 1
fi

exec /usr/bin/open -n "$APP_BUNDLE" --args "$@"
