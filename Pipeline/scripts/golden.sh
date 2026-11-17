#!/usr/bin/env bash
# The golden check: proof that a change to the pipeline's code leaves the reference data
# it builds exactly as it was.
#
#   scripts/golden.sh record   build with the code as it is now, and keep a copy of the
#                              output in work/golden/ (gitignored)
#   scripts/golden.sh          build again and compare with that copy, byte for byte; with
#                              no copy recorded, compare with what git holds
#
# Record before the change, check after it. A recorded copy, not git, is the usual
# baseline because the committed data can lag the code: the data committed in b7b0c58 was
# built before c22b7e1 changed how Wikipedia titles match, so the code at HEAD already
# builds two places differently from git, and a check against git would blame that on
# whatever change came next.
#
# The build writes in place, into the app's resources and content/ids. So the script
# will not start unless those folders match git, and puts them back as git has them when
# it finishes: a check leaves the checkout as it found it.
#
# The manifest records the day it was built. The check holds that date to the baseline's
# (SOURCE_DATE_EPOCH), so a check run on another day is not a difference.

set -euo pipefail

PIPELINE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$PIPELINE/.." && pwd)"
REFERENCE="Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference"
IDS="Pipeline/content/ids"
GOLDEN="$PIPELINE/work/golden"
MODE="${1:-check}"

case "$MODE" in
	record | check) ;;
	*)
		echo "usage: scripts/golden.sh [record|check]" >&2
		exit 2
		;;
esac

cd "$REPO"

if [[ -n "$(git status --porcelain --untracked-files=all -- "$REFERENCE" "$IDS")" ]]; then
	echo "golden: these differ from git, so a build here could overwrite work in progress:" >&2
	git status --short --untracked-files=all -- "$REFERENCE" "$IDS" >&2
	echo "golden: commit them or set them aside, then run again." >&2
	exit 2
fi

restore() {
	git restore --worktree -- "$REFERENCE" "$IDS"
	git clean -fdq -- "$REFERENCE" "$IDS"
}
trap restore EXIT

epoch_of() {
	python3 -c '
import datetime, json, sys
day = json.load(open(sys.argv[1]))["builtOn"]
moment = datetime.datetime.fromisoformat(day).replace(tzinfo=datetime.timezone.utc)
print(int(moment.timestamp()))
' "$1"
}

if [[ "$MODE" == check && -d "$GOLDEN/reference" ]]; then
	baseline="the copy recorded in work/golden ($(head -n 1 "$GOLDEN/RECORDED"))"
	epoch="$(epoch_of "$GOLDEN/reference/manifest.json")"
else
	baseline="git"
	epoch="$(epoch_of "$REFERENCE/manifest.json")"
fi

echo "golden: building the reference data (about a minute)"
(cd "$PIPELINE" && SOURCE_DATE_EPOCH="$epoch" PYTHONPATH=src \
	uv run python -m unigrids_pipeline reference --skip-fetch)

if [[ "$MODE" == record ]]; then
	rm -rf "$GOLDEN"
	mkdir -p "$GOLDEN"
	cp -R "$REFERENCE" "$GOLDEN/reference"
	cp -R "$IDS" "$GOLDEN/ids"
	{
		echo "$(date -u +%Y-%m-%dT%H:%MZ) from $(git rev-parse --short HEAD)"
		echo "Pipeline code not yet committed when this was recorded:"
		git status --short -- Pipeline/src Pipeline/content
	} >"$GOLDEN/RECORDED"
	echo "golden: recorded in work/golden; run scripts/golden.sh after the change"
	exit 0
fi

status=0
if [[ "$baseline" == git ]]; then
	git diff --exit-code --stat -- "$REFERENCE" "$IDS" || status=1
	untracked="$(git ls-files --others --exclude-standard -- "$REFERENCE" "$IDS")"
	if [[ -n "$untracked" ]]; then
		echo "golden: the build added files git does not have:"
		echo "$untracked"
		status=1
	fi
else
	for pair in "reference:$REFERENCE" "ids:$IDS"; do
		recorded="$GOLDEN/${pair%%:*}"
		built="${pair#*:}"
		if ! diff -rq -x .DS_Store "$recorded" "$built"; then
			diff -ru -x .DS_Store "$recorded" "$built" | head -n 80 || true
			status=1
		fi
	done
fi

if [[ $status -eq 0 ]]; then
	echo "golden: identical to $baseline"
else
	echo "golden: the build differs from $baseline (above)" >&2
fi
exit $status
