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
