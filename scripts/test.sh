#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
swiftc -swift-version 6 -parse-as-library Sources/ClipNest/HistoryStore.swift Tests/ClipNestTests/HistoryStoreTests.swift -o .build/checks/history-checks
.build/checks/history-checks

swift scripts/generate-icon.swift .build/checks/TestIcon.iconset
swiftc -swift-version 6 -parse-as-library Sources/ClipNest/ThumbnailLoader.swift Tests/ClipNestTests/ThumbnailLoaderChecks.swift -o .build/checks/thumbnail-checks
.build/checks/thumbnail-checks

swiftc -swift-version 6 -parse-as-library Sources/ClipNest/KeyboardRouting.swift Tests/ClipNestTests/KeyboardRoutingChecks.swift -o .build/checks/keyboard-checks
.build/checks/keyboard-checks
