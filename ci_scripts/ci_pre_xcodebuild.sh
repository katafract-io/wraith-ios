#!/bin/zsh -e
# Xcode Cloud CI pre-build: set CFBundleVersion = CI_BUILD_NUMBER + 100
# so it always climbs past any agvtool/manual build number on ASC.
BUILD_NUM=$((CI_BUILD_NUMBER + 100))
echo "ci_pre_xcodebuild: setting CFBundleVersion to $BUILD_NUM (CI_BUILD_NUMBER=$CI_BUILD_NUMBER)"
cd "$CI_PRIMARY_REPOSITORY_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "WraithVPNMacTunnel/Info.plist"
