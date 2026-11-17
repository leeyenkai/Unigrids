# Content for countries after the US

Hand-written and version-controlled, like the US content one level up, and under the same
rule: **never invent a fact.** Every figure, date and claim is checked against at least
two sources — the park authority's own page first, then Wikipedia (English or the
country's own) or a regulation — and anything that cannot be confirmed is left out. An
absent figure renders as absent; a plausible wrong one reaches the reader as truth.

```
countries/
  jp/national-parks.json      the 35 parks: id, MOE English name, page slug, Japanese name, region
  jp/guides/<id>.json         one guide per park (below)
  no/national-parks.json      the 48 parks: id, short official name, Naturvernområder id
  no/guides/<id>.json
```

Identifiers in the park lists are permanent. Guides are named by them:
`jp/guides/jp-np-shiretoko.json`, `no/guides/no-np-jotunheimen.json`.

## A guide

The US guide format (`../guides/np-zion.json`) with these differences: sights always
carry a location, because there is no NPS places feed to match them to; the facts the US
reads from `national-park-facts.json` are in the guide; and the prose the US takes from the
NPS API (weather, getting there, fees) is written here.

```jsonc
{
  "placeID": "no-np-jotunheimen",
  "contentVersion": 1,
  "summary": "40–80 words: what the place is and why anyone goes.",
  "facts": {
    "establishedYear": 1980,            // first protected as a national park
    "areaHectares": 115100,             // Norway: the current regulation's figure (Lovdata); Svalbard's 1973 parks, whose regulations give none, the Norwegian Polar Institute's; Japan: MOE's national park table
    "bestSeasons": ["summer", "autumn"],
    "suggestedTime": "Three to five days"
    // elevation is measured by the pipeline; do not write it here
  },
  "story": ["3–4 paragraphs of 60–120 words: geology, ecology, people, the park's making"],
  "howItWorks": [
    "2–3 paragraphs. Japan: the park as a zoned regional park — who owns the land, the towns, shrines and farms inside it, the special protection zone and special zones, what that means for a visitor. Norway: the right to roam as it applies here, the summer fire ban, the park's own protection rules (motor traffic, drones, dogs, calving and nesting restrictions with their dates). Svalbard: the Svalbard Environmental Protection Act and the field-safety regulation (FOR-2025-06-06-940): notification, polar bears, the travel area."
  ],
  "sights": [
    {"name": "Besseggen", "note": "≤ 30 words.", "location": [61.501, 8.761]},
    {"name": "Memurubu", "note": "…", "location": [61.507, 8.783], "kind": "viewpoint"},
    {"name": "Norsk Fjellmuseum", "note": "…", "location": [61.837, 8.568], "kind": "visitorCentre"}
  ],
  "planYourVisit": {
    "entrances": [], "reservations": "…", "permits": [], "camping": [], "lodging": [],
    "seasonalClosures": ["Sognefjellet road (Fv55) closes for the winter"],
    "seasonalClosureMonths": [11, 12, 1, 2, 3, 4, 5]
  },
  "weather": "One paragraph on the climate a visitor meets, month by month in outline.",
  "directions": "One paragraph on getting there: rail, bus, ferry and road.",
  "fees": [
    {"title": "Climbing fee, Yoshida Trail", "cost": "¥4,000", "amount": 4000,
     "currencyCode": "JPY", "detail": "…"}
  ],
  "chronology": [{"year": "1962", "text": "…"}],
  "safety": ["3–5 items"],
  "regulations": ["3–5 items"],
  "themes": ["theme-mountains", "theme-glaciers"],
  "photos": [
    {"file": "File:Besseggen.jpg", "caption": "Besseggen between Gjende and Bessvatnet",
     "altText": "A narrow ridge between a green lake and a blue one"}
  ],
  "sources": [{"title": "Jotunheimen nasjonalpark — Norges nasjonalparker",
               "url": "https://www.norgesnasjonalparker.no/nasjonalparker/jotunheimen/"}]
}
```

- **Sights**: five to eight, ranked by order; every location from a source you can cite
  (Wikipedia's coordinates, OpenStreetMap, the official map), to three or more decimals
  and inside or at the edge of the park. Visitor centres and authorised national park
  centres (`"kind": "visitorCentre"`) as well, with their location. Huts come from
  OpenStreetMap in the pipeline; do not list them.
- **Photos**: four Wikimedia Commons files of the park itself, hero first, each a real
  file name you have seen on Commons. The pipeline reads each file's credit and licence
  from Commons; captions and alternative text are yours.
- **Themes**: the IDs in `../themes.json`.
- **Seasonal rules**: anything that changes each season (reservations, fees, road
  openings, fire bans) is worded "check before you go", with the authority named.
- **Units and style**: metric in prose; British spelling; plain, concrete sentences in
  the voice of the US guides. Local names in their own script where it helps the reader
  (知床五湖 Shiretoko Goko).

## Sources and licences

The owner's call for this private app: licences are not a reason to leave a source out,
but every source used is named — in the guide's `sources`, on the Attributions screen and
in `NOTICE.md`. Prose is written for Unigrids, never copied.
