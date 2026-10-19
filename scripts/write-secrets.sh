#!/usr/bin/env bash
# Write the app's gitignored Secrets.plist from the NPS API key in `.env`.
#
# The key turns on live park alerts in guides. Without it the app builds and runs
# normally, and the alerts panel simply does not appear. The key is never printed, and
# the plist it lands in is gitignored (AGENTS.md "Secrets"). Run again after changing
# the key; pass --remove to delete the plist and build without alerts.
source "$(dirname "$0")/common.sh"

PLIST="$REPO_ROOT/App/Unigrids/Secrets.plist"

if [[ "${1:-}" == "--remove" ]]; then
	rm -f "$PLIST"
	say "Removed Secrets.plist; live alerts are off in the next build"
	exit 0
fi

key="${NPS_API_KEY:-}"
if [[ -z "$key" && -f "$REPO_ROOT/.env" ]]; then
	# Read the one line we need rather than sourcing the whole file.
	key="$(grep -E '^NPS_API_KEY=' "$REPO_ROOT/.env" | tail -1 | cut -d= -f2- | tr -d '"'"'"' \r')"
fi

if [[ -z "$key" ]]; then
	echo "No NPS_API_KEY in the environment or in .env; nothing written." >&2
	echo "Get a free key at https://www.nps.gov/subjects/developer/get-started.htm" >&2
	exit 1
fi

if ! git -C "$REPO_ROOT" check-ignore -q "$PLIST"; then
	echo "Refusing to write $PLIST: it is not gitignored." >&2
	exit 1
fi

umask 077
rm -f "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NPSAPIKey string $key" "$PLIST" >/dev/null
say "Wrote App/Unigrids/Secrets.plist (gitignored); live alerts are on in the next build"
