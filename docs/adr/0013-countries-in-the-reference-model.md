# 13. Countries in the reference model

Date: 2026-11-16

## Status

Accepted

## Context

Unigrids began as a guide to US public lands, and the model said so everywhere. A place
was located by `USState`, typed by US agency enums, filed in one of the nine NPS passport
regions (falling back to Western), and keyed by NPS park codes. Stats divided by the 56
states and territories and the nine regions. The America 250 seal went on every stamp
dated 2026, wherever it was made.

The next milestone adds the national parks of Japan and Norway, and their second tier:
Japan's quasi-national parks, Norway's protected landscapes and major nature reserves.
Left as it was, a Japanese park would decode with an empty state list, stamp in the
Western region's ink under "Beyond the NPS", count towards nothing, and carry an
AMERICA 250 seal in 2026. `USState` decodes any code it is given, so a prefecture code
written into `states` would show as a fake state everywhere.

User records point at reference data only by ID string, so none of this touches the log's
schema.

## Decision

**A country on every place.** `Country` in `UnigridsCore` (`US`, `JP`, `NO`) carries its
name and its national park system's authority. `Place.country` decodes with a default of
the United States, so today's bundle decodes unchanged.

**Subdivisions beside states, not instead of them.** `Subdivision` holds an ISO 3166-2 code
and name: Japan's 47 prefectures, Norway's 15 counties and Svalbard. A US place derives its
subdivisions from `states`; a Japanese or Norwegian place carries them and keeps `states`
empty. `USState`, the US tile map, the state time-zone fallback and the passport's state
assignments stay US-only.

**The country can be read from an ID.** New places are namespaced (`jp-np-…`, `no-np-…`,
`jp-qnp-…`, `no-lvo-…`, `no-nr-…`); every ID minted before this decision is American. So a
record whose place has left the dataset still knows its country
(`Country.inferred(from:)`), which the America 250 rule needs.

**No silent US defaults abroad.** A foreign place always carries its agency, passport
region and time zone; tests hold that invariant rather than letting the US fallbacks
(Western, the NPS, a state's zone) fill the gap.

**Totals are per country.** Counts that used to be the US's alone — national parks,
regions, states — are asked for by country, with tests pinning the US figures.

## Consequences

- Every US figure, string and output stays as it was until data for another country
  ships; country-specific screens appear only when that country has data.
- `MapFilter` gains a hand-written decoder before any field is added, because its
  synthesized one would reset every saved filter.
- An older build reading a log that holds Japanese or Norwegian visits shows them as
  unknown places, and would put the seal on their 2026 stamps. That is acceptable for an
  old build and is noted in the specification.
- Adding a fourth country is data plus a `Country` case, its regions and its
  subdivisions — not another pass through the model.
