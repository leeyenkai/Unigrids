# Shared settings for the scripts in this directory. Source, do not run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/Packages/UnigridsKit"
XCODE_PROJECT="$REPO_ROOT/App/Unigrids.xcodeproj"
SCHEME="Unigrids"

# SwiftPM builds outside the repository.
#
# This checkout sits in a folder backed by a macOS file provider (iCloud Desktop &
# Documents), which stamps `com.apple.FinderInfo` on files it manages. `codesign`
# refuses to sign a bundle carrying that attribute — "resource fork, Finder
# information, or similar detritus not allowed" — so `swift test` fails when its
# build directory is inside the synced folder. Building elsewhere avoids it entirely,
# and is faster besides. Harmless on a checkout that is not synced.
SCRATCH_PATH="${UNIGRIDS_SCRATCH_PATH:-$HOME/Library/Caches/Unigrids/spm}"

swift_in_package() {
	mkdir -p "$SCRATCH_PATH"
	(cd "$PACKAGE_DIR" && swift "$@" --scratch-path "$SCRATCH_PATH")
}

say() {
	printf '\n\033[1m==> %s\033[0m\n' "$1"
}

# This checkout lives in a folder iCloud syncs, and iCloud answers a file rewritten while
# it is uploading with a "conflict copy" beside it — `Deletion 2.swift`, `np-zion 2.json`.
# A Swift copy fails the build with duplicate symbols; a JSON copy ships inside the app
# without a word. Refuse to go on while any is present.
check_conflict_copies() {
	local found
	found=$(find "$REPO_ROOT/Packages" "$REPO_ROOT/App" \
		\( -name "* [0-9].*" -o -name "* [0-9]" \) -not -path "*/.build/*" 2>/dev/null)
	if [[ -n "$found" ]]; then
		printf '\n\033[1;31m==> iCloud conflict copies in the tree:\033[0m\n%s\n' "$found" >&2
		echo "Delete them (they are stale copies), then run this again." >&2
		exit 1
	fi
}
