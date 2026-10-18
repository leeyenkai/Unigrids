# Curated content

Files here are **hand-written and version-controlled**, not generated. The pipeline reads
them in its `edit` step, validates them, and folds them into the built dataset.

| Directory | Holds |
|---|---|
| `guides/` | Guide text per park, where it is edited as prose rather than as JSON |
| `curated/` | Permit and timed-entry rules, seasonal notes, passport region assignments, theme overrides, sight rankings |

Two of these need curation that does not exist yet, both tracked in `SPECIFICATION.md`
§17:

- **Passport region assignments** for NPS sites, from the paper passport (follow-up 3).
  Until they exist, `PassportRegion.byState` is the fallback, and it is Unigrids' own
  grouping rather than the paper book's.
- **The busy state parks** that get offline packs (follow-up 1).
