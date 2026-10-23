# Changelog

All notable changes to Unigrids are recorded here.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until `1.0.0`,
minor versions are the milestones in [`SPECIFICATION.md`](SPECIFICATION.md) §16: `0.1.0`
is the four-park pilot, `0.2.0` the MVP, `1.0.0` the full release.

Every user-visible change adds a line under `## [Unreleased]` in the same commit that
makes the change. A release moves that block under a version heading with its date.

## [Unreleased]

### Fixed

- The map no longer stalls while a place card slides in on iPad. Its five thousand pins
  and outlines are rebuilt only when the filter, the log or the alerts change, not on
  every redraw.

## [0.9.0] — 2026-10-23

The production pass: everything below, from the first pilot to this release. Widgets and
the Watch app keep `1.0.0` open.

### Added

- Repository scaffolding: `README.md`, `.gitignore`, `.editorconfig`, SwiftFormat and
  SwiftLint configuration, a GitHub Actions workflow, and `scripts/` for bootstrap, build,
  test and lint.
- `AGENTS.md` working agreement, with `CLAUDE.md` pointing at it.
- `SPECIFICATION.md`, carried over from the design document and now the living source of
  truth for requirements.
- `docs/mvp-scope.md` recording what the `0.1.0` pilot covers and what it deliberately
  does not.
- Architecture decision records 0001–0004.
- `UnigridsKit` Swift package with five modules — `UnigridsCore`, `UnigridsReference`,
  `UnigridsLog`, `UnigridsDesign`, `UnigridsFeatures` — and a thin `App/` target for
  iPhone, iPad and Mac.
- Domain model in `UnigridsCore`: places and their tiers, points of interest, trails,
  guide content, themes, the nine passport regions, and the America 250 seal rule.
- Deterministic stamp impressions: tilt, offset and ink density derive from a stored seed,
  so an impression renders identically every time it is drawn.
- `UnigridsReference` bundled-data loader with a hand-authored pilot seed covering all 63
  national parks by name, state and location, with deep guide content for Zion, Acadia,
  Yellowstone and Great Smoky Mountains.
- `UnigridsLog` SwiftData store for trips, visits, check-ins, stamps and weather
  snapshots, configured for the private CloudKit database.
- Map home screen: national park pins, tier styling, visited and planned badges, search,
  and a bottom card with check-in and guide actions.
- Parks directory with search and sort.
- Unigrid-style park guide: title band, at-a-glance panel, story, sights, visitor centres
  and chronology, in a grid that collapses from four columns to one with Dynamic Type.
- Passport tab: the nine regions, slot pages, a stamp sheet with date entry, and the
  America 250 overprint on stamps dated in 2026.
- Stats tab: parks and states visited, a completion ring, and visits by year.
- Visit log with manual check-in, editing and deletion.
- Offline Python pipeline skeleton (`Pipeline/`) with the fetch, match, derive, edit,
  build and package steps stubbed and documented.
- Four selectable colour palettes — Unigrid, Press, Canyon and Tidewater — and a separate
  appearance setting of Dark, Light or Automatic, both in Settings. Dark is the default.
  The choice is a per-device display preference and does not sync with the log.
- A written design system in [`docs/design-system.md`](docs/design-system.md), and
  ADR 0005 recording why colour is data in `UnigridsCore` rather than `Color` in the views.
- One icon vocabulary (`UnigridsSymbol`) in place of fifty-odd scattered symbol strings,
  with a test that every name resolves against the SDK.
- An app icon, where there was none: Zion Canyon as a true perspective heightfield under
  a blue desert sky, with three Unigrid brochures laid across it as sheets of frosted
  glass — each with its park named on the black band in Helvetica caps-and-lower-case, a
  photograph, a map panel and columns of set type. Each sheet prints its own park —
  Zion's sandstone, the Grand Canyon's strata, Yosemite's granite — so the pile reads as three
  different brochures rather than one printed three times. Light, dark and tinted
  variants plus the ten macOS sizes, all generated deterministically by
  [`Tools/IconGenerator`](Tools/IconGenerator) from the brochure system's own proportions
  and each park's own geology, and anti-aliased in the renderer itself rather than left
  to supersampling.
- Nine more app icons, one per park, switchable in Settings: Grand Canyon, Yosemite,
  Sequoia, Rocky Mountain, Olympic, Acadia, Joshua Tree, Everglades and Congaree. The
  park you pick stands behind the stack and its brochure is the one on top. iPhone and
  iPad only — macOS has no alternate app icons, and on the Mac the row says so rather
  than offering a control that would do nothing.
- The pipeline's `fetch`, `derive` and `build` steps, for one park and without an API key:
  NPS boundaries and Public Trails, USGS 3DEP elevation and OpenStreetMap roads and water,
  each versioned by date under `Pipeline/raw/` with its licence recorded beside it.
- Trail measurement in the pipeline: length, elevation gain and loss, high and low points
  and an elevation profile, every trail measured the same way from its route line and
  3DEP — resampled at 10 m, smoothed over 50 m, accumulated with a 3 m dead band so
  elevation-model noise does not read as climb. Zion comes to 44 trails and 116 km.
- Offline park packs: topo-style relief tiles rendered from 3DEP, OpenStreetMap and NPS
  trails in the style of an NPS brochure map, written as WebP in MBTiles alongside the
  measured trails, a manifest and the attribution the sources oblige the pack to carry.
- `Pipeline/out/pack-size-report.md`, which measures the pack and costs all 63 parks
  against the App Store's 4 GB limit from each park's own boundary.
- ADR 0006 recording the pack format and why.
- **Reference data built by the pipeline** rather than hand-seeded: `unigrids_pipeline
  reference` fetches the NPS Data API, NPS unit boundaries, USGS PAD-US, Wikipedia and
  Wikimedia Commons into a dated snapshot and builds 537 places — all 63 national parks,
  373 other NPS units, 76 state parks and 25 monuments, conservation areas and refuges —
  with 1,434 sights, visitor centres and campgrounds, 506 outlines and 235 photographs.
- **A detailed atlas map.** Every place is a marker whose shape is its tier and whose
  colour is its agency; national parks are outlined at every zoom and named on black
  plates, the rest outlined from regional zoom and clustered at country scale. A tap or
  click anywhere inside an outline selects the place. Region shortcuts for the Lower 48,
  Alaska, Hawaiʻi, the Caribbean and the Pacific; a map key that opens filters by tier
  and visited status; search across places and sights; a muted, hybrid or satellite base
  map.
- **An overview for every place**, opened from the map: photograph and credit, a written
  summary, figures, visit status, and check in, stamp, add to trip, open the guide and
  directions in Maps. A sheet on iPhone, an inspector beside the map on iPad and Mac.
- **Guides for all 63 national parks**, written for Unigrids and checked against the NPS
  and Wikipedia: a summary, the story, sights placed on the park map, visitor centres,
  plan your visit, chronology, safety, regulations and sources, with date established,
  area and 2025 visits for every park.
- New guide panels from the NPS's own data: a photo gallery, entrance fees and hours,
  weather and seasons, and getting there; live park alerts when the build has an NPS key.
- A park map panel with the outline and numbered sights, and **Explore in 3D**, which
  flies the camera between a park's sights.
- A page for each of the other 474 places, and written overviews for all 101 curated
  state parks, monuments and refuges.
- **Trip planning:** trips with ordered, dated stops, a route map, straight-line
  distance, reordering, a calendar (`.ics`) export, and Add to trip from every place.
  Planned places show dashed on the map, and a check-in can join a trip.
- Stats rebuilt: a national park grid, a tile map of every state and territory, headline
  figures, visits by year and by theme, the nearest unvisited park, and a share card.
- Passport rebuilt: region rows with completion, and an America 250 page.
- Export the whole log as JSON, and visits as CSV, from Settings.
- A three-panel welcome with the non-affiliation notice, shown once and available again
  from Settings.
- A Photo credits screen listing every photograph with its credit and licence, and
  attributions for USGS PAD-US, Wikimedia Commons and Open-Meteo.
- `scripts/write-secrets.sh`, which writes the gitignored `Secrets.plist` the app reads its
  NPS key from.
- ADR 0007 (one identity across every screen) and ADR 0008 (the home map wraps
  `MKMapView`).
- **Every federal land on the map, outlined.** 2,052 places, up from 537: every national
  forest and grassland from the Forest Service, 548 national wildlife refuges from Fish
  and Wildlife, the BLM's national monuments and conservation areas, all 575 National
  Natural Landmarks and 186 national scenic byways and All-American Roads, each from its
  agency's own published data. 1,260 places are outlined and every outline draws at every
  zoom, a lighter version of each at country scale so the whole map stays quick.
- **A pictogram for every kind of place.** Eighteen site types — national park, monument,
  historic site, battlefield, memorial, seashore, recreation area, river, parkway,
  preserve, forest, grassland, refuge, conservation area, natural landmark, byway, state
  park and other — each with its own symbol inside the tier's marker. The map key lists
  them by group and filters by them.
- **Roads and rail on the map.** A Layers menu draws the Interstate Highway System, the US
  routes on the National Highway System and every Amtrak route, with its stations once
  the map is close enough to read them, from the US DOT's National Transportation Atlas.
  Scenic byways draw as routes in their own ink.
- Map filters by site type, visited status, state, activity and stamp location, with a
  count of what each leaves; live alert badges on parks with a posted closure or danger,
  from regional zoom.
- **Explore in 3D**, now a full 3D view for any place: realistic-elevation terrain in
  satellite, hybrid or standard, the outline, numbered sights, visitor centres and the
  park's trails; a list of sights (a sidebar on iPad and Mac) where choosing one flies
  the camera there and opens its card; a guided tour that flies sight to sight and circles
  each; a reset to the overview; and Look Around where Apple has imagery.
- **A trail catalogue** for 59 national parks: 3,239 trails from the NPS Public Trails
  dataset, each measured from its line and USGS 3DEP elevation — distance, climb, high and
  low point, an elevation profile, an estimated time and an estimated difficulty — with
  sights along the way and permitted uses. Filters by distance, climb, difficulty, route
  type, feature and not yet hiked; Mark as hiked, in full or in part, feeds the log and
  the stats. A guide's trail highlights now come from the catalogue.
- **Official maps and brochures.** Each NPS site's maps and brochures, as its own nps.gov
  pages list them, open in a PDF viewer and are kept on device once opened. Places on an
  upcoming trip are saved ahead, Save for offline covers any other, and Settings lists
  what is kept with its size. A site with no PDF listed opens its maps page instead.
- A climate panel in each national park guide: average monthly high, low and rainfall
  over 2016–2025, from the Open-Meteo archive.
- **By train**: the nearest Amtrak station to a place's outline, how far it is and which
  services call there, on guides and leaflets.
- **Planner:** drive times between stops from Apple Maps, a total per day and a warning
  past six hours at the wheel; flags on a stop for posted closures and dangers, reservation
  notes and seasonal closures; a 16-day forecast for each dated stop; reminders for
  permits, timed entry and booking windows as local notifications; the roads drawn on
  the trip's map; and a GPX export of the stops.
- **Weather for every visit**, fetched once from Open-Meteo when a visit is logged and kept,
  and a weather section in Stats: hottest, coldest and wettest visits.
- **Auto-detected visits** on iPhone and iPad, off until turned on in Settings: with
  Always location, the app watches the places nearest you and asks "Log a visit?" on
  arrival. Nothing is logged until you say so, and no location is stored.
- **Import from Photos**: geotagged photos matched to places on device, grouped into
  proposed visits and trips to accept or leave. Visits keep photo references, never copies.
- Passport slots for each official stamp location, an impressions sheet showing every
  stamp in a slot, and a passport page exported as an image.
- Stats sections for kinds of place visited and visits by month; distance walked and
  climb from hiked trails.
- Undo after deleting a visit, trip or stamp.
- On the Mac, a guide or leaflet opens in its own window beside the map.
- A fourth welcome panel, on the planner, and a welcome key that shows the new markers.
- **Richer trips.** A stop can be a place, a sight, visitor centre or campground inside
  it, a trail, lodging, or any point on the way found by name; each draws its own marker
  on the trip map, routes from its own position, and exports to Calendar and GPX. Add
  several stops at once from places, from what is inside the trip's parks, or from an
  Apple Maps search. A stop's details sheet sets its day, an optional time in the park's
  zone, and notes, and takes it off the trip with undo. "Add to trip" on sight,
  facility and trail cards.
- **Mark as hiked** asks which day and whether it went the whole way, joins that day's
  visit, and offers undo. A trail's page lists the hikes logged on it, each deletable.
- A trail mapped one way reads "4.2 km one way · 8.4 km there and back".
- An arrival waiting for an answer badges the Trips tab.
- **When to go.** A national park's Weather and seasons panel charts visitors by month
  beside the climate, and an NPS site's leaflet has a "When it's busy" panel — the mean of
  the NPS's own monthly recreation visits over 2022–2025, busiest month marked.
- NPS sites without a full guide show the NPS's hours, fees, reservations, directions and
  contact on their leaflet.
- An overview adapted from Wikipedia says so under it, names and links the article, and
  carries its CC BY-SA 4.0 licence. Heights measured from USGS 3DEP say they were
  measured. A trail drawn from OpenStreetMap credits it under the ODbL. A state park names
  the body that runs it. Settings credits NPS visitor statistics and Wikipedia.
- **Offline park maps** for Zion, Acadia, Yellowstone and Great Smoky Mountains: a
  topographic Park map with every trail and sight that works with no signal, from the
  guide, a trail's page ("On the park map"), or in place of Explore in 3D when the device
  is offline. Settings lists the maps and their sizes. ADR 0010.
- **Every state park.** 3,539 state parks from PAD-US, up from 76, each with its outline,
  its manager, and — for 2,722 places across the map with no agency prose — a credited
  Wikipedia lead. Nine parks PAD-US still lists but whose articles say they have closed
  are left out.
- Trails for Sequoia and Kings Canyon, 267 of them from OpenStreetMap, measured like every
  other park's. 3,486 of 3,506 trails are measured.
- Every place carries its own time zone; NPS sites carry monthly visitation and their
  visitor information; 42 parks gain a measured elevation range; 226 passport stamp
  locations are places of their own.
- **Alert notifications** for parks on trips under way or starting within 30 days: a new
  danger or closure posted by the NPS arrives as a notification that opens the park —
  through background app refresh on iPhone and iPad, every three hours while the app is
  open on the Mac. Quiet (provisional) until you choose otherwise.
- **Share cards** for most Stats sections, a visit and a trip, as well as your parks:
  shown before they are sent, made on the device, handed to the share sheet.
- **Year in review**: a year's visits, places new to you, national parks (new ones marked),
  states, busiest month and distance hiked, with its own card.
- **In a row**: the months and years in a row you have logged a visit, now and at most.
- **Your data, all of it.** The JSON export holds every record and field — visits,
  trips, stops, reminders, check-ins, hikes, stamps and weather — and Settings › Your data
  imports it back, merging by record so nothing doubles. Delete all my data sits behind a
  confirmation.
- **Undo for every change**: deleting a visit, trip, stamp, stop, reminder or hike, and
  stamping, logging a hike or importing, each offer "Undo" where they happened, announced
  to VoiceOver.
- **One sheet for every task**: every sheet opens on the same band and paper, with Cancel
  and its action, or Done, where each platform puts them.
- Notifications open what they are about: an arrival its log sheet, a reminder its trip,
  an alert its park.
- A privacy manifest (no tracking, no data collected), and the entitlements the Mac's
  hardened runtime needs for location and Photos, so "Where am I", stamp verification and
  photo import work there.

### Changed

- **One design language on every screen.** The brochure identity now runs through the
  map, directory, trips, passport, stats and settings as well as the guides: a black band
  opens each screen, sections open with ruled caps heads, figures are set large, buttons
  and markers are square, and a palette now restyles every screen's paper and ink.
- Panels side by side in a guide share one height, so a row reads as a single sheet.
- The Parks directory can show national parks or every place.
- The Parks directory gains a Trails scope and a site-type filter, and each row carries
  its place's marker.
- The map shows detail by zoom: country-scale outlines and national park pins at first,
  pins for forests, refuges and other large lands from regional zoom, station markers
  close up. National parks keep a compact pin when zoomed far out.
- The 25 hand-curated monuments, conservation areas and refuges are replaced by the
  agencies' own lists, so each carries the agency's name and designation as published.
- A place with no written summary now shows a line built only from its own fields — "A
  national forest in Colorado, managed by the US Forest Service." — rather than nothing.
- Search matches a two-letter state code to the places in that state, and ranks national
  parks first.
- The overview panel names who designated a place and shows a byway's mapped length.
- **Map pins redrawn so each kind of place is unmistakable.** Pins are now solid, in a
  colour per kind of place — national parks black, monuments crimson, history brown,
  water blue, forests and preserves green, refuges teal, BLM land amber, landmarks
  magenta, state parks violet, byways orange — with a white symbol and a white keyline
  that hold on any base map. National parks carry a star; other public land is a hexagon
  instead of a cramped diamond. Visited places get a green tick and planned ones a
  dashed ring, and outlines take the same colours as their pins
  ([ADR 0009](docs/adr/0009-pins-coloured-by-kind-of-place.md)).
- With the whole country in view, national parks gather into a starred count where they
  would overlap, instead of piling on top of each other; group counts are now round.
- The map key explains colour, shape, ticks, rings, alert corners and groups, and its
  chip on the map is a strip of colour swatches.
- Trips are grouped Under way, Planned and Done, by their dates; "New trip" opens the trip
  it makes, and an end date can no longer fall before the start.
- A visit on a trip opens the same editor as any other: its day, trip, rating and
  notes, its check-ins with their photos, its hikes (deletable) and its stamps. Moving
  it to another day moves everything logged on it. Deleting it says what goes with it.
- The map keeps its filters between launches and says so in a line under the region
  shortcuts — "Filtered · 212 of 5,524 · Clear" — and says when roads and rail are still
  loading or failed to. Search says when nothing matches, and a sight chosen from it is
  marked on the map. A park's map card lists its posted alerts, where the badge leads.
  "Where am I" explains a refusal and offers Settings.
- The region shortcuts split "Pacific", which only ever showed American Samoa, into
  "Guam & N. Marianas" and "American Samoa".
- Settings opens from every tab on iPhone and iPad, and on the Mac from the app menu
  (⌘,) only. It says what is on the map in plain words.
- The national parks count comes from the data everywhere it is shown, rather than a
  fixed 63; searching National parks searches the parks themselves; By state lists a park
  under each of its states. Onboarding can be skipped, and says what the app does now.
- Trail highlights show in every park guide with catalogued trails; they were hidden in
  all of them, waiting on a hand-made list no guide had. Trails a guide names lead.
- On iPhone a guide's toolbar holds Explore in 3D and one More menu; "See it in 3D" is
  "Explore in 3D" everywhere.
- Reminders open to edit, show their time in the zone they were set in, and can be set
  in the park's zone or the device's.
- Import from Photos counts photos read out of the total, offers Open Settings when access
  is refused, reckons each photo's day at the place it was taken, and undoes a whole
  import in one step.
- The map key, photo viewer, Look Around, the 3D explorer's list and the reminder editor
  share the sheet shell the rest of the app uses.
- One vocabulary everywhere: every icon comes from the app's symbol table (Directions has
  its own sign; the car means driving), and each action has one name — Open guide and Open
  page, Add to trip, Website, Check in, Stamp, Delete.
- Buttons wrap to a second line instead of shrinking their type, and paired buttons stack
  at the largest text sizes. Remaining fixed-size text follows Dynamic Type.
- The place card, explorer cards, passport pages, America 250 and Photo credits open with
  the same band as every other screen.
- State parks show as pins from regional zoom, like forests and refuges: three and a half
  thousand at country scale were a blanket of cluster counts. Their outlines still show.

### Fixed
- **The log can no longer vanish.** If the store would not open, the app used to carry on
  with an in-memory copy and lose everything logged that session at quit; a background
  relaunch before the first unlock was enough. It now waits for the unlock, retries, and
  otherwise says the data is safe on disk and offers Retry. The Mac log has its own file
  instead of SwiftData's shared default, moved there once after checking it is this app's.
- One visit per place per day, however it is logged; the day is the place's own. Deleting
  a visit takes its stamps, so the passport and the map always agree. Moving a visit to
  another day moves everything logged on it.
- Days are reckoned in the Gregorian calendar at the place: on a phone set to the Buddhist
  or Japanese calendar the America 250 seal never applied and weather was asked for days
  that do not exist.
- CSV export writes the visit's own day, quotes every kind of line break, and never
  starts a field like a formula.
- Weather for a visit is the day's observed weather, never the forecast it was logged
  with; a visit that cannot be filled stops being asked about after three tries.
- Live alerts survive one bad record (the whole feed used to go blank), page past the
  first 500, and back off after a failure to spare the shared key.
- Passport regions follow the paper book, checked against 329 regional stamps: Arizona is
  Western, Virginia and Maryland Mid-Atlantic, the Dakotas Rocky Mountain, and the sites
  the book files elsewhere follow it.
- Arrival suggestions keep watching after moving their watched set, and asking for Always
  location no longer gives up after eight seconds.
- Brochures are kept out of backups and downloaded once, off expensive networks.
- Reminders fire at the moment they name in the zone they were set in, stop when their
  trip is deleted, and no longer crash when deleted from the list.
- A trip's dates are kept at noon, so a trip planned in one time zone reads as the same
  days in another.
- The offline Park map fills the corners of its box the pack never drew with blank paper,
  instead of patches of Apple's map.
- Notes under the Trips, Passport, Trails and explorer lists sit on the page's own paper;
  as list footers they drew as a black strip on every palette.
- Names an agency wrote with capital small words read properly — "Statue of Liberty",
  "War in the Pacific", "Crater of Diamonds" — without changing any place's identifier.

- The map key's chip drew four pins that ran into each other; the key's "reading the map"
  section described the old hollow pins.
- The Stamp button drew nothing. `stamp` and `stamp.fill` are not SF Symbols in any
  version, so five places — the guide's Stamp action, the place card, Trips, the visitor
  centre panel and the stamp sheet — rendered a blank space where an icon belonged. They
  now draw the app's own cancellation mark.
- Settings on the Mac reported zero visits and zero stamps. The `Settings` scene was never
  given the model container its queries read from.
- Passport stamps, agency pin colours and the park-green accent are legible in dark mode.
  Every one of the nine region inks failed WCAG AA on a dark page, four of them at even the
  lowest bar, and the accent sat at 1.95:1 where 3:1 is the minimum. Each colour now has a
  dark variant of the same hue, and a parameterised test holds every palette, scheme and
  pairing to AA so this cannot silently come back.

- Park areas no longer print spurious precision in metric locales: Acadia read
  `19,859.947893 ha` instead of `19,860 ha`.
- Measurement units now follow `.us` rather than `== .metric`. `Locale.MeasurementSystem`
  has three cases and the UK reports `.uk`, so British readers were being shown park
  elevations in feet.
- On the Mac, sheets built on a list — the stop picker, Add to trip, map filters, the
  stamp sheet and the photo viewer — collapsed to a sliver and showed nothing.
- On the Mac, the welcome screens showed a tab strip; they now page with Back and Next.
- Map camera moves requested from a search or a region shortcut landed one step late.
- A trip's map now reframes when stops are added or removed, and the stop picker leaves
  out places already on the trip.

### Notes

- Reference data is now pipeline output from a 2026-10-19 snapshot. Its provenance, photo
  policy and limits are recorded in
  `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md`.
- **Zion's offline pack is 22.2 MB** — 5,063 tiles at zoom 10–16, 256 px WebP, clipped to
  the park boundary plus a 2 km buffer. That was the pilot's open question
  (`SPECIFICATION.md` §16).
- **4 GB holds, with WebP and a per-park zoom cap: 2.2 GB for all 63 parks.** It does not
  hold at full depth everywhere (12.4 GB), and it does not hold in any PNG form at all
  (149 GB). Tile format is worth eight times over and costs nothing the eye can find; six
  Alaskan park-and-preserve units are 77 % of the national tile count. State parks cost
  about 2 MB each and are not a budget question. The brochure PDFs are the one part of the
  budget still unmeasured. The figures and what to trim are in
  [`docs/mvp-scope.md`](docs/mvp-scope.md).
- Offline map packs exist in the pipeline but not in the app: nothing reads a pack, so
  `package` deliberately does not copy one into the app's resources. Widgets, the Watch
  app and an "open this season" filter are not built. See
  [`docs/mvp-scope.md`](docs/mvp-scope.md).
- Trail difficulty is an estimate from distance and climb by Shenandoah National Park's
  published formula, and says so wherever it shows: the NPS trails layer publishes no
  difficulty. Sequoia, Kings Canyon, Gates of the Arctic and Kobuk Valley have no trails
  of their own in that layer (its one Kobuk Valley segment is Klondike's Chilkoot Trail,
  mis-filed, which the outline check drops), so those four parks show no catalogue.
- Forecasts and visit weather come from Open-Meteo rather than WeatherKit, which needs a
  development team the build does not have yet (`SPECIFICATION.md` §17).
- iPhone layouts were checked on an iOS 26.5 Simulator, from a throwaway copy with the
  deployment target lowered; the development machine still has no iOS 27 runtime. iPad
  was not checked.

[Unreleased]: https://github.com/leeyenkai/Unigrids/commits/main
