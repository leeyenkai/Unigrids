# 14. Six countries

Date: 2026-11-17

## Status

Accepted. Extends [ADR 0013](0013-countries-in-the-reference-model.md). Updated
2026-11-18 with what was decided in building: which Australian parks, the second-tier
thresholds, the facts left absent, and the published grades. The sources are in
[`docs/sources-nz-au-ca.md`](../sources-nz-au-ca.md).

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
- **Which Australian parks get a guide.** A fixed rule, each park recorded with its
  reason in `Pipeline/content/countries/au/national-parks.json`: the six Commonwealth
  parks; every state or territory national park wholly or partly within one of
  Australia's World Heritage properties — where a property takes in more than eight
  (the Gondwana Rainforests, the Wet Tropics, the Great Barrier Reef), only those UNESCO's
  description or the agency's own page names as its principal parks; and each state's
  flagship as its agency presents it. That came to 6, 34 and 11: **51**, not the forty
  first expected. They are `.nationalPark`. Every other national park CAPAD records (666)
  is `.stateNationalPark`: a national park by name, drawn and tiered as a state park, with
  its outline, area, managing agency and, where one matches, a credited Wikipedia
  summary.
- **Second tiers.** New Zealand's conservation and forest parks of 5 km² or more
  (`.conservationPark`; 49 — DOC records access strips and outlying parcels as parks of
  their own, which the threshold keeps off the map); Canada's national marine
  conservation areas (`.marineConservationArea`; 5) and provincial and territorial parks
  of 100 km² or more by CPCAD's official area (`.provincialPark`; 254, Québec's *parcs
  nationaux* among them, labelled provincial whatever their name). Te Urewera, expected
  among the conservation parks, is not on the map: since the Te Urewera Act 2014 it is not
  conservation land, and DOC's layer does not carry it.
- **Canada's national parks are Parks Canada's list**: its 47 national parks and national
  park reserves and Rouge National Urban Park, 48, each joined to CPCAD by parent ID.
  Pituamkek, an interim reserve in CPCAD the list does not name, is left out.
- **Facts the sources disagree on stay absent.** A guided park's founding year and area
  are its guide's, from the managing agency. CAPAD's gazettal date is not a founding year
  — it is when the land now in a park was last gazetted, and it disagreed with the
  agency's year for 11 of 44 guided Australian parks — so it never stands in; seven
  Australian parks show no year. An area is left absent where the sources disagree
  (Kakadu, Naracoorte Caves, Nitmiluk, Mingan Archipelago, Bruce Peninsula) or the agency
  gives none (Thousand Islands). New Zealand's guides fall back to DOC's recorded area for
  the land, never the outline's measured area. An Australian second-tier park takes
  CAPAD's gazetted area where it agrees with the mapped area to within 25 %, else the
  mapped area. The bundled tests name each park that knowingly lacks a year, an area or
  three sights, with the reason, in `KnownGaps`; any other gap fails them.
- **Published grades.** `TrailGrade.System` gains `newZealandTrackCategory` (DOC's six
  track categories), `parksCanadaDifficulty` (Easy to Most difficult) and
  `australianWalkingTrackGrade` (grades 1 to 5, read from Queensland's track classes to
  AS 2156.1). Each shows as published and files under the five difficulty bands; the
  bands are Unigrids' reading. New South Wales and Victoria publish no open grades, so
  their trails keep the estimate.
- **Attendance by fiscal year.** Parks Canada counts April to March; a count carries its
  period and reads "Visitors, 2025–26", never a calendar year it does not cover.
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
- Every place in the three countries is outlined, so the map draws them all as the US's
  outlined places are drawn.
- Live warnings follow each country's own services (GeoNet; Environment Canada and
  Avalanche Canada; five state fire services and the NSW NPWS). South Australia, the
  Northern Territory and the island territories publish no readable feed, so their parks
  claim none rather than an empty list.
- The new kinds reuse existing inks — the state parks' for state national parks and
  provincial parks, conservation's for conservation parks, water's for marine areas — so
  the palette stays at eleven colours and the ΔE and contrast tests keep holding.
