# 14. Six countries

Date: 2026-11-17

## Status

Accepted. Extends [ADR 0013](0013-countries-in-the-reference-model.md).

## Context

0.11.0 adds New Zealand, Australia and Canada to the US, Japan and Norway, at the same
depth: every national park with a full guide, the second tier as pins and leaflets, a
passport book each. ADR 0013 made the model country-aware, but three of its assumptions
do not hold for the new countries:

- **One zone per country.** Japan and Norway each keep one time zone, so a place abroad
  with no recorded zone fell back to its country's. Australia spans five, Canada six
  (Newfoundland half an hour off the rest), and New Zealand's Chatham Islands keep their
  own, 45 minutes ahead of the mainland.
- **One authority per country.** Australia's national parks are run by its six states and
  two territories; only six are the Commonwealth's (three jointly with their Traditional
  Owners). About 715 parks carry the name "national park".
- **A second tier that is plainly second.** Australia's state national parks are national
  parks by name; Canada's provincial parks include Québec's *parcs nationaux*.

## Decision

- **Zones by subdivision.** `Subdivision.mainTimeZoneID` names the zone of each
  Australian state and territory, each Canadian province and territory, and the Chatham
  Islands; `UnigridsCalendar.timeZone(for:)` reads it after the place's own zone and the
  US state's, and before the country's. Every bundled place still carries its own zone.
- **Subdivisions.** New Zealand's sixteen regions and the Chatham Islands Territory
  (ISO 3166-2:NZ); Australia's states and mainland territories (ISO 3166-2:AU) plus
  Christmas Island, Cocos (Keeling), Norfolk Island and Jervis Bay under `AU-` codes of
  our own (ISO lists the first three as countries, and Jervis Bay has no code); Canada's
  thirteen provinces and territories (ISO 3166-2:CA). A stamp's foot names an Australian
  state or Canadian province by its short code (NSW, BC), as their own post marks them.
- **Agencies.** `Agency` gains New Zealand's Department of Conservation, Parks Australia,
  Parks Canada and a provincial agency. An Australian state's park keeps `.stateAgency`,
  with `managedBy` naming the agency (NPWS, Parks Victoria, QPWS).
- **Which Australian parks get a guide.** The six Commonwealth parks, and the state parks
  inside an Australian World Heritage property or named its state's best-known by its
  agency — about forty, fixed in `Pipeline/content/countries/au/national-parks.json`. They
  are `.nationalPark`. Every other state national park is `.stateNationalPark`: a
  national park by name, drawn and tiered as a state park, with its outline, official
  facts and a credited summary.
- **Second tiers.** New Zealand's conservation and forest parks and Te Urewera
  (`.conservationPark`); Canada's national marine conservation areas
  (`.marineConservationArea`) and provincial parks of 100 km² or more (`.provincialPark`,
  Québec's *parcs nationaux* among them, labelled provincial whatever their name).
- **Passport books.** New Zealand's three regions (North Island; Upper South Island;
  Lower South Island and Rakiura), Australia's eight (its states and territories, the
  island territories together) and Canada's six (Atlantic, Québec, Ontario, Prairies,
  Mountains and Pacific, North) are Unigrids' own, each with a light and a dark ink held
  to 4.5:1. The date line is `07.11.2026` in New Zealand, `07 NOV 2026` in Australia and
  `2026-11-07` in Canada.
- **The map.** The world view reaches from Rakiura to Canada's Arctic islands. Where two
  countries' views overlap — the Lower 48 box reaches into southern Ontario — the smallest
  view holding a point decides whose map it is. The Chatham Islands, east of 180°, keep a
  box of their own rather than one that wraps.

## Consequences

- No user data changes: records point at places by ID, and the new IDs are namespaced
  `nz-`, `au-`, `ca-`.
- Every `switch` over `Country`, `PlaceKind`, `SiteType` and `PassportRegion` names the
  new cases; the compiler finds each one.
- The new kinds reuse existing inks — the state parks' for state national parks and
  provincial parks, conservation's for conservation parks, water's for marine areas — so
  the palette stays at eleven colours and the ΔE and contrast tests keep holding.
