#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:-}"
if [[ "$mode" != local && "$mode" != notarized ]]; then
  echo "Usage: $0 local|notarized" >&2
  exit 1
fi
version="$(tr -d '\n\r' < VERSION)"
output="$PWD/.build/releases/$version/$mode"
app="$output/ClipNest.app"
mkdir -p "$output"
if [[ "$mode" == notarized ]]; then
  : "${CLIPNEST_SIGN_IDENTITY:?Set Developer ID Application signing identity}"
  : "${CLIPNEST_NOTARY_PROFILE:?Set an existing notarytool keychain profile name}"
  export CLIPNEST_RELEASE=1
else
  # Local archives are explicitly ad-hoc, never mistaken for notarized releases.
  export CLIPNEST_RELEASE=0
  export CLIPNEST_SIGN_IDENTITY=-
fi
CLIPNEST_APP_OUTPUT="$app" CLIPNEST_REGISTER_APP=0 CLIPNEST_UNIVERSAL=1 ./scripts/build-app.sh
lipo "$app/Contents/MacOS/ClipNest" -verify_arch arm64 x86_64
if [[ "$mode" == notarized ]]; then
  submission="$output/notary-upload.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
  xcrun notarytool submit "$submission" --keychain-profile "$CLIPNEST_NOTARY_PROFILE" --wait --output-format json > "$output/notarization.json"
  notary_status="$(plutil -extract status raw -o - "$output/notarization.json")"
  [[ "$notary_status" == Accepted ]] || { echo "Notarization was not accepted; see $output/notarization.json" >&2; exit 1; }
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
  archive="$output/ClipNest-$version-universal.zip"
else
  archive="$output/ClipNest-$version-universal-unsigned.zip"
fi
# Create the distributable archive AFTER stapling the notarization ticket.
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$output" && shasum -a 256 "${archive:t}" > SHA256SUMS.txt)
echo "Archive: $archive"
echo "Checksum: $output/SHA256SUMS.txt"
