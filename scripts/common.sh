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
