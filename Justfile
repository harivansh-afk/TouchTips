set shell := ["zsh", "-cu"]

default: gen

# Generate TouchedTips.xcodeproj from project.yml
gen:
    [ -f configs/Local.xcconfig ] || cp configs/Local.example.xcconfig configs/Local.xcconfig
    xcodegen generate

open: gen
    open TouchedTips.xcodeproj

# Build the app for the simulator without opening Xcode
build: gen
    xcodebuild -project TouchedTips.xcodeproj -scheme TouchedTips -destination 'generic/platform=iOS Simulator' -quiet build

# Run the core package tests (no simulator needed)
test:
    swift test --package-path Packages/TouchedTipsCore

fmt:
    swiftformat Sources Packages/TouchedTipsCore/Sources Packages/TouchedTipsCore/Tests

# Formatting check only. Feel/ is excluded in .swiftformat: those files are mixbridge's, byte for byte.
lint:
    swiftformat Sources Packages/TouchedTipsCore/Sources Packages/TouchedTipsCore/Tests --lint

# The gate before a PR: core build and tests, then a device build with any warning counted as a failure.
check: gen
    #!/usr/bin/env zsh
    set -eu
    swift build --package-path Packages/TouchedTipsCore
    swift test --package-path Packages/TouchedTipsCore
    log=$(xcodebuild -project TouchedTips.xcodeproj -scheme TouchedTips -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates -derivedDataPath build/dd -quiet build 2>&1) || { echo "$log"; exit 1 }
    if print -r -- "$log" | grep -q "warning:"; then
        print -r -- "$log" | grep "warning:"
        echo "warnings are failures" >&2
        exit 1
    fi
    echo "check passed"

# Build for a plugged-in iPhone and install it. Needs DEVELOPMENT_TEAM in configs/Local.xcconfig.
device: gen
    #!/usr/bin/env zsh
    set -eu
    xcodebuild -project TouchedTips.xcodeproj -scheme TouchedTips -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates -derivedDataPath build/dd -quiet build
    id=$(xcrun devicectl list devices --hide-headers --hide-default-columns --columns Identifier --columns State \
        | awk '$2 == "connected" || $2 == "available" { print $1; exit }')
    if [ -z "$id" ]; then
        echo "no available iPhone: plug one in, unlock it, and trust this Mac" >&2
        exit 1
    fi
    xcrun devicectl device install app --device "$id" build/dd/Build/Products/Debug-iphoneos/TouchedTips.app
