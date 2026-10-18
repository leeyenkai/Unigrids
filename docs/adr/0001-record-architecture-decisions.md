# 1. Record architecture decisions

Date: 2026-10-18

## Status

Accepted

## Context

`SPECIFICATION.md` says what the app should do and §2 records the product decisions
already taken. It does not say why the code is shaped the way it is, and those reasons
are the ones that get lost: a future contributor — or a coding agent reading the repo
cold — will otherwise re-litigate a settled choice or quietly break the reason for it.

## Decision

Architectural decisions with lasting weight are recorded here as short, numbered,
immutable records. A record states the context, the decision and its consequences. A
decision that is later reversed gets a new record that supersedes the old one; the old
record stays, marked superseded.

What belongs here: module boundaries, data storage, dependency choices, anything that
would be expensive to change later. What does not: product scope (that is the
specification), or how a single screen is laid out.

## Consequences

One more file to write when a real decision is made, and a cheap answer to "why is this
like this?" that does not depend on anyone's memory. `AGENTS.md` points contributors here.
