#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version="$(tr -d '\n\r' < VERSION)"
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Invalid VERSION" >&2; exit 1; }
sandbox_mode="${CLIPNEST_SANDBOX:-1}"
bundle_id="com.clipnest.app"
app_name="ClipNest"
sign_options=()
if [[ "$sandbox_mode" == 1 ]]; then
  bundle_id="com.clipnest.sandbox"
  sign_options=(--entitlements "$PWD/config/Sandbox.entitlements")
fi
signing_identity="${CLIPNEST_SIGN_IDENTITY:--}"
release_mode="${CLIPNEST_RELEASE:-0}"
if [[ "$release_mode" == 1 && "$signing_identity" == - ]]; then
  echo "Release signing requires CLIPNEST_SIGN_IDENTITY (Developer ID Application)." >&2
  exit 1
fi

# Build into a separate bundle: preparing a release never modifies the running app.
default_app="$PWD/.build/$app_name.app"
if [[ "$sandbox_mode" == 1 ]]; then default_app="$PWD/.build/sandbox/$app_name.app"; fi
app="${CLIPNEST_APP_OUTPUT:-$default_app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${CLIPNEST_UNIVERSAL:-0}" == 1 ]]; then
  binaries=()
  for architecture in arm64 x86_64; do
    scratch="$PWD/.build/architectures/$architecture"
    swift build -c release --arch "$architecture" --scratch-path "$scratch"
    binary_dir="$(swift build -c release --arch "$architecture" --scratch-path "$scratch" --show-bin-path)"
    binaries+=("$binary_dir/ClipNest")
  done
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/ClipNest"
else
  swift build -c release
  binary_dir="$(swift build -c release --show-bin-path)"
  cp "$binary_dir/ClipNest" "$app/Contents/MacOS/ClipNest"
fi
swift scripts/generate-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipNest</string>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>$app_name</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "$release_mode" == 1 ]]; then
  codesign --force --sign "$signing_identity" "${sign_options[@]}" --options runtime --timestamp "$app"
  signature="$(codesign -dvv "$app" 2>&1)"
  [[ "$signature" == *'Authority=Developer ID Application:'* ]] || {
    echo "Distribution requires a Developer ID Application certificate." >&2; exit 1;
  }
else
  codesign --force --sign "$signing_identity" "${sign_options[@]}" "$app"
fi
codesign --verify --strict --verbose=2 "$app"
if [[ "${CLIPNEST_REGISTER_APP:-1}" == 1 ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
  touch "$app"
fi
echo "Built: $app ($version)"
