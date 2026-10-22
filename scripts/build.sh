#!/usr/bin/env bash
# Build the real app for both platforms.
#
# A green package is not proof the app links: run this before claiming an app-level
# change works (AGENTS.md §2).
source "$(dirname "$0")/common.sh"
check_conflict_copies

# Each platform's full log is kept in a temporary file and only its errors, warnings and
# result printed. The script fails if either build does: piping xcodebuild straight into
# grep once hid a failed build behind a zero exit.
build() {
	local destination="$1"
	local label="$2"
	local log
	log="$(mktemp -t unigrids-build)"
	say "Building for $label"
	local result=0
	xcodebuild \
		-project "$XCODE_PROJECT" \
		-scheme "$SCHEME" \
		-destination "$destination" \
		-configuration "${CONFIGURATION:-Debug}" \
		build >"$log" 2>&1 || result=$?
	grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" "$log" || true
	if [[ $result -ne 0 ]]; then
		echo "The $label build failed; full log in $log"
	fi
	return $result
}

status=0
build 'generic/platform=iOS Simulator' 'iOS Simulator' || status=1
build 'platform=macOS' 'macOS' || status=1
exit $status
