set shell := ["zsh", "-cu"]

default: gen

# Generate TouchTips.xcodeproj from project.yml
gen:
    [ -f configs/Local.xcconfig ] || cp configs/Local.example.xcconfig configs/Local.xcconfig
    xcodegen generate

open: gen
    open TouchTips.xcodeproj

# Build the app for the simulator without opening Xcode
build: gen
    xcodebuild -project TouchTips.xcodeproj -scheme TouchTips -destination 'generic/platform=iOS Simulator' -quiet build

# Run the core package tests (no simulator needed)
test:
    swift test --package-path Packages/TouchTipsCore

fmt:
    swiftformat Sources Packages/TouchTipsCore/Sources Packages/TouchTipsCore/Tests

# Build for a plugged-in iPhone and install it. Needs DEVELOPMENT_TEAM in configs/Local.xcconfig.
device: gen
    #!/usr/bin/env zsh
    set -eu
    xcodebuild -project TouchTips.xcodeproj -scheme TouchTips -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates -derivedDataPath build/dd -quiet build
    id=$(xcrun devicectl list devices --hide-headers --hide-default-columns --columns Identifier --columns State \
        | awk '$2 == "available" { print $1; exit }')
    if [ -z "$id" ]; then
        echo "no available iPhone: plug one in, unlock it, and trust this Mac" >&2
        exit 1
    fi
    xcrun devicectl device install app --device "$id" build/dd/Build/Products/Debug-iphoneos/touchtips.app
