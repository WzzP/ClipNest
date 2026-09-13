#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CLIPNEST_SANDBOX=1 CLIPNEST_RELEASE=0 CLIPNEST_SIGN_IDENTITY=- \
  CLIPNEST_APP_OUTPUT="$PWD/.build/sandbox/ClipNest.app" ./scripts/build-app.sh
