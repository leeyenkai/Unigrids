#!/usr/bin/env bash
# Formatting and lint checks. Pass --fix to apply formatting rather than check it.
source "$(dirname "$0")/common.sh"

FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

status=0

if command -v swiftformat >/dev/null; then
	say "SwiftFormat"
	if [[ $FIX -eq 1 ]]; then
		swiftformat "$REPO_ROOT"
	else
		swiftformat --lint "$REPO_ROOT" || status=1
	fi
else
	echo "swiftformat not installed; skipping (brew install swiftformat)"
fi

if command -v swiftlint >/dev/null; then
	say "SwiftLint"
	(cd "$REPO_ROOT" && swiftlint lint --quiet) || status=1
else
	echo "swiftlint not installed; skipping (brew install swiftlint)"
fi

if command -v uv >/dev/null; then
	say "Pipeline (ruff)"
	(cd "$REPO_ROOT/Pipeline" && uv run --quiet --with ruff ruff check .) || status=1
else
	echo "uv not installed; skipping the pipeline checks"
fi

exit $status
