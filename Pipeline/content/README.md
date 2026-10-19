# Curated content

Files here are **hand-written and version-controlled**, not generated. The `reference`
build reads them and folds them into the bundled dataset.

The rule for every fact here is the repository's: **never invent one.** Each guide was
written from the NPS Data API record and the park's Wikipedia article and checked fact by
fact; anything that could not be confirmed was left out. A missing figure renders as
absent, which is correct.

| File or directory | Holds |
|---|---|
| `national-parks.json` | The 63 national parks: id, name, states, centre, NPS park code (and API code where parks share one, as Sequoia and Kings Canyon do), themes |
| `national-park-facts.json` | Date established, area and 2025 recreation visits for each park, with sources |
| `state-parks.json`, `federal-sites.json` | The curated state parks, monuments and refuges: PAD-US name patterns for the outline, Wikipedia article for the photograph, and a written summary |
| `themes.json` | Theme tags |
| `guides/np-*.json` | One guide per national park: summary, at-a-glance extras, story, sights (matched to NPS places by name, or given a location), plan your visit, chronology, safety, regulations, sources |
| `curated/` | Permit and timed-entry rules, seasonal notes, passport region assignments, theme overrides, sight rankings |

Two of these need curation that does not exist yet, both tracked in `SPECIFICATION.md`
§17:

- **Passport region assignments** for NPS sites, from the paper passport (follow-up 3).
  Until they exist, `PassportRegion.byState` is the fallback, and it is Unigrids' own
  grouping rather than the paper book's.
- **The busy state parks** that get offline packs (follow-up 1).
