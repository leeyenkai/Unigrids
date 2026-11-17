#!/usr/bin/env bash
# The fast loop: the whole UnigridsKit suite, without Xcode's build system.
source "$(dirname "$0")/common.sh"
check_conflict_copies

say "Testing UnigridsKit"
# Warnings are errors, as in CI (AGENTS.md §3).
swift_in_package test -Xswiftc -warnings-as-errors "$@"
