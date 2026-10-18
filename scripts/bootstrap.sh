#!/usr/bin/env bash
# Check the toolchain and resolve dependencies.
source "$(dirname "$0")/common.sh"

say "Toolchain"
if ! command -v xcodebuild >/dev/null; then
	echo "xcodebuild not found. Install Xcode 27 or later." >&2
	exit 1
fi
xcodebuild -version | head -2
swift --version | head -1

say "Resolving UnigridsKit"
swift_in_package package resolve

say "Optional tools"
for tool in swiftformat swiftlint uv; do
	if command -v "$tool" >/dev/null; then
		printf '  %-12s %s\n' "$tool" "$(command -v "$tool")"
	else
		printf '  %-12s missing (brew install %s)\n' "$tool" "$tool"
	fi
done

say "Ready"
echo "  scripts/test.sh    run the UnigridsKit suite"
echo "  scripts/build.sh   build the app for iOS Simulator and macOS"
echo "  scripts/lint.sh    format and lint checks"
