#!/usr/bin/env bash
# Build the real app for both platforms.
#
# A green package is not proof the app links: run this before claiming an app-level
# change works (AGENTS.md §2).
source "$(dirname "$0")/common.sh"

build() {
	local destination="$1"
	local label="$2"
	say "Building for $label"
	xcodebuild \
		-project "$XCODE_PROJECT" \
		-scheme "$SCHEME" \
		-destination "$destination" \
		-configuration Debug \
		build \
		| grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true
}

build 'generic/platform=iOS Simulator' 'iOS Simulator'
build 'platform=macOS' 'macOS'
