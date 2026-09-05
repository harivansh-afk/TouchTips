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

# Stream the app's own log lines from the plugged-in iPhone. No debugger, so background behaviour is real.
log:
    idevicesyslog -p TouchTips | grep --line-buffered 'TouchTips(TouchTips'

# Run the core package tests (no simulator needed)
test:
    swift test --package-path Packages/TouchTipsCore

fmt:
    swiftformat Sources Packages/TouchTipsCore/Sources Packages/TouchTipsCore/Tests

# Formatting check only. Feel/ is excluded in .swiftformat: those files are mixbridge's, byte for byte.
lint:
    swiftformat Sources Packages/TouchTipsCore/Sources Packages/TouchTipsCore/Tests --lint

# The gate before a PR: core build and tests, then a device build with any warning counted as a failure.
check: gen
    #!/usr/bin/env zsh
    set -eu
    swift build --package-path Packages/TouchTipsCore
    swift test --package-path Packages/TouchTipsCore
    log=$(xcodebuild -project TouchTips.xcodeproj -scheme TouchTips -destination 'generic/platform=iOS' \
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
    xcodebuild -project TouchTips.xcodeproj -scheme TouchTips -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates -derivedDataPath build/dd -quiet build
    id=$(xcrun devicectl list devices --hide-headers --hide-default-columns --columns Identifier --columns State \
        | awk '$2 == "connected" || $2 == "available" { print $1; exit }')
    if [ -z "$id" ]; then
        echo "no available iPhone: plug one in, unlock it, and trust this Mac" >&2
        exit 1
    fi
    xcrun devicectl device install app --device "$id" build/dd/Build/Products/Debug-iphoneos/TouchTips.app
