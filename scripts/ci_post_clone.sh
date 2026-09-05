#!/bin/sh
# Xcode Cloud runs this after cloning, before it looks for the project.
# TouchTips.xcodeproj is gitignored, so generate it here, then stamp the
# build number with Xcode Cloud's counter.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen

printf 'DEVELOPMENT_TEAM = %s\n' "${DEVELOPMENT_TEAM:-G2U3K77U5W}" > configs/Local.xcconfig
xcodegen generate

# CURRENT_PROJECT_VERSION is a target setting, which outranks any xcconfig, so edit the generated project.
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" TouchTips.xcodeproj/project.pbxproj
echo "build number ${CI_BUILD_NUMBER}"
