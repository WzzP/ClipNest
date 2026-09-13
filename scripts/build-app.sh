#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app="$PWD/.build/ClipNest.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift scripts/generate-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp .build/release/ClipNest "$app/Contents/MacOS/ClipNest"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipNest</string>
<key>CFBundleIdentifier</key><string>com.clipnest.app</string>
<key>CFBundleName</key><string>ClipNest</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Set this to an installed Apple Development / Developer ID identity to keep
# the designated requirement stable across builds. Ad-hoc remains a local fallback.
signing_identity="${CLIPNEST_SIGN_IDENTITY:--}"
codesign --force --sign "$signing_identity" "$app"
# Refresh Launch Services after replacing an existing development bundle so
# Finder does not retain the placeholder from the first icon-less build.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
touch "$app"
echo "Built: $app"
