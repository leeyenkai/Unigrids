# Unigrids — App Specification (Draft v0.1)

2026-10-16 · Lee Yen Kai

## 1. Overview

Unigrids is a free, native Apple app (iPhone, iPad, Mac) for planning, exploring and logging visits to US public lands, all on one map. National parks get the deepest treatment: an interactive guide designed in the style of the NPS Unigrid brochures, the official brochure itself, a 3D view, and a trail catalogue. Other NPS sites, state parks and major federal sites appear as rich map pins.

Who it is for: park collectors and road-trippers who want to plan trips, keep a record of where they have been, and see their travels as stats. The first user is the developer; it ships as a hobby/portfolio app.

Principles

- Homage, not imitation: guides borrow the clarity of the 1977 Vignelli Unigrid system; content is factual and built from public-domain NPS material.
- Privacy-first: data stays on device and in the user's iCloud. No accounts, no social feed; sharing is by exported cards.
- Depth before breadth: national parks are excellent before other tiers gain depth.
- Works without signal where it matters: park maps and trails ship inside the app.
- Nothing to run: no servers or hosting of my own, only Apple services and public APIs.

## 2. Decisions so far

These came out of two brainstorm rounds on 16 Oct 2026 and frame the rest of this draft.

| Area | Decision |
|---|---|
| Release | Free hobby/portfolio app, private for now; no monetisation |
| Infrastructure | No servers or hosting of my own; the app talks directly to Apple Maps, WeatherKit, iCloud and the NPS API (key built into the app) |
| Content delivery | Database, guides and offline packs bundled in the app, within the App Store's 4 GB limit; brochures fetched from NPS on first open and cached on device |
| Platforms | iPhone, iPad and Mac on the latest OS only; widgets and an Apple Watch app in v1 |
| Relation to Antipodes | Separate app with the same privacy model; fully independent code and data |
| Coverage | Tiered: national parks get full guides, 3D and trails; other NPS sites, state parks and major federal sites get rich pins |
| Territories | All US territories on the map and in stats |
| Unigrids | A native Unigrid-style guide for each national park, plus the official brochure viewer for every NPS site |
| Guide text | Adapted from public-domain NPS text, lightly edited |
| 3D | Apple Maps 3D (MapKit) with Unigrids pins and overlays on top |
| Trails | Trail catalogue and offline maps; no live GPS recording or workout import for now |
| Offline maps | Own topo tiles + trails inside MapKit for national parks and a curated set of busy state parks; 3D stays online-only |
| Logging | Manual check-ins, auto-detected visits, photo-library import, and a passport stamp book organised by region, with an America 250 seal on every stamp dated 2026 |
| Passport | Nine regions: paper-passport assignments for NPS sites, by state for everything else; stamp any place on any date, with a verified tick when stamped on site; America 250 seal for calendar year 2026 |
| Planning | Trip itineraries, live NPS alerts, permit and timed-entry reminders, weather and seasons |
| Design | Unigrid look applies to park guides only; map, log, planner and stats use a native look |
| Major sites | National forests and grasslands, BLM national monuments and conservation areas, national wildlife refuges, all National Natural Landmarks, nationally designated scenic byways and All-American Roads |
| State parks | PAD-US, patched from state agency data where it is thin |
| Stats | Completion and coverage, weather and season, themes and landscapes, trail distance and elevation |
| Pilot | Zion, Acadia, Yellowstone and Great Smoky Mountains |

## 3. Platforms and tech stack

One SwiftUI codebase targets iPhone, iPad and Mac. There is no server or hosting of any kind: reference data and offline packs ship inside the app, brochures load from NPS's own servers, and user data lives in SwiftData synced through the user's private iCloud.

| Layer | Choice | Notes |
|---|---|---|
| UI | SwiftUI, multiplatform target | Native Mac app, not Catalyst; latest OS generation only; WidgetKit widgets and a watchOS app in v1 |
| Maps and 3D | MapKit | Realistic-elevation terrain, satellite/hybrid imagery, pitched camera and fly-to animations; pins, polygons and polylines as overlays |
| Offline maps | MapKit with app-supplied tiles | Apple's own offline maps are not available to third-party apps; MapKit can draw tiles the app supplies. The SwiftUI Map view may need an MKMapView wrapper for tile overlays (verify on the current SDK) |
| Brochure viewer | PDFKit | Zoom, pan, page-turn between brochure sides; PDFs fetched from NPS and cached on device |
| User data | SwiftData + CloudKit private database | Trips, visits, check-ins, stamps, plans |
| Reference data | Read-only SQLite bundled in the app | Parks, sights, trails, themes; updated with each app release |
| Weather | WeatherKit + Open-Meteo archive | WeatherKit for forecasts and recent history; Open-Meteo for older visits |
| Location | Core Location | Geofence and visit monitoring for auto-detected visits and the verified stamp tick |
| Photos | PhotoKit | On-device scan of geotags for trip back-fill |
| Charts | Swift Charts | Stats section |
| Notifications | UserNotifications + background refresh | Alerts for parks on upcoming trips; permit and booking reminders |
| Data pipeline | Python, run locally or on a schedule | Builds the database and offline packs into the app's resources, and records a checked NPS brochure link for every site |

Antipodes: fully independent, with no shared packages or data.

## 4. App structure and navigation

Five tabs (Map, Parks, Trips, Passport, Stats) share one place database and one visit log, so a check-in made anywhere shows up everywhere.

> _Diagram in source doc: app structure · 5 tabs, 22 screens_

Map and Parks are the two ways into a park; Trips, Stamps and Stats all read the same log. The Unigrid guide is the app's signature screen, reachable from a map pin, the directory or a trip stop.

## 5. Map home screen

The app opens on a map of every covered place in the US, with national parks always visible and other tiers revealed as the user zooms in. There are 63 national parks and roughly 433 NPS units as of mid-2026 ([WorldAtlas](https://www.worldatlas.com/national-parks/how-many-states-have-a-national-park.html), [Citizen Daily Post](https://www.citizendailypost.com/faq/how-many-national-parks-are-in-the-us/)); the pipeline should read the live list from the NPS API rather than hard-code it.

| Tier | What it covers | Depth in the app |
|---|---|---|
| 1 | National parks (63) | Full Unigrid guide, official brochure, 3D view, trail catalogue, offline pack, stamps |
| 2 | Other NPS units (monuments, seashores, historic sites, etc.) | Rich pin: overview, hours, fees, live alerts, visitor centres, stamp locations, official brochure |
| 3 | State parks | Pin and boundary, type, basic facts, link to the official page |
| 4 | Major federal sites: national forests and grasslands, BLM monuments and conservation areas, wildlife refuges, national natural landmarks, scenic byways | Pin or line (byways), boundary, agency, basic facts |

Behaviour

- Pins differ by tier and agency (shape and colour); visited places show filled, planned places show an outline badge.
- Pins cluster at country scale; park boundaries appear as tinted polygons from regional zoom.
- Alaska, Hawaii and the territories are one tap away through region shortcuts.
- Filters: tier and agency, visited or not, state, activity (hiking, camping, scenic drive), open this season, has a stamp location.
- Search covers parks, sights, trails and visitor centres.
- Tapping a pin opens a bottom card: name, type, states, two or three quick facts, visit status, and actions (Open guide, Explore in 3D, Check in, Add to trip, Directions in Apple Maps).
- Live alert badges (closures, fire, roads) show on parks that have active NPS alerts.

As built for the MVP (`0.2.0`)

- 537 places: the 63 national parks, 373 other NPS units (heritage areas, trails, affiliated and administrative units are left out), 76 curated state parks and 25 curated federal sites — BLM national monuments and a conservation area, Forest Service monuments and Fish and Wildlife refuges. National forests, grasslands, natural landmarks and byways are not in yet.
- 506 places are outlined. National park outlines show at every zoom; the others appear below a latitude span of about 14°. A tap or click inside an outline selects the place, as well as a tap on its marker ([ADR 0008](docs/adr/0008-mapkit-atlas.md)).
- Marker shape is the tier and colour the agency ([ADR 0007](docs/adr/0007-one-identity-across-every-screen.md)); smaller sites cluster into numbered squares; national parks never cluster and carry a black name plate from regional zoom.
- Filters are tier and visited status. State, activity, season and stamp filters are not built.
- The bottom card is an overview panel — a sheet on iPhone, an inspector on iPad and Mac — with a photograph and credit, a written summary, figures, visit status and actions.
- Base map: muted map, hybrid or satellite. Live alert badges on the map are not built; alerts show in guides.

## 6. Park guides and official brochures

Each national park has two linked views: a native, interactive guide laid out like a Unigrid, and the official NPS brochure as published. The native guide is the everyday reading view; the brochure is the authentic artefact, one tap away.

Native Unigrid-style guide (panels, top to bottom)

1. Title band: park name in white on the black band, designation and states beneath.
2. Hero image: a public-domain NPS photo, credited.
3. At a glance: established year, area, elevation range, annual visits, entrance fee, best seasons, suggested time.
4. The story: three or four short paragraphs on the park's geology, ecology and history.
5. Map panel: the official brochure map (public domain), interactive, with tappable visitor centres and sights.
6. Major sights: ranked list with a photo, one line each, and a seen-it check.
7. Visitor centres: location, hours, services, stamp availability.
8. Trail highlights: the park's top trails, linking to the catalogue.
9. Plan your visit: entrances, reservations or timed entry, permits, camping and lodging, seasonal closures, live alerts.
10. Chronology: a timeline panel, echoing the timelines in many Unigrid brochures.
11. Safety, regulations, credits and sources.

Layout by device

- iPhone: one column, panels stacked; a landscape "unfolded" view shows two panels side by side.
- iPad: two to three grid columns, closer to a brochure spread.
- Mac: three to four columns in a resizable window; a guide can open in its own window beside the map.

Official brochure viewer

- Shows each park's current brochure PDF, both sides, with zoom and pan in PDFKit.
- Available for every NPS site. The PDF is fetched from NPS's own site the first time it is opened and kept on device; parks on an upcoming trip are saved for offline automatically, and a Save for offline toggle covers any other park. Cached brochures are listed in Settings with their size and can be cleared. If a stored link breaks, the viewer opens the park's NPS maps page instead.
- Displayed as published with its credits; photos or art inside it are not extracted for reuse, since some may carry third-party rights (see section 15).
- Later: an archive of past brochure editions per park.

Content sources: NPS API fields (description, fees, hours, visitor centres, things to do, places) and NPS web text, lightly edited for length and to fit the panel structure.

As built for the MVP (`0.2.0`)

- Every national park has a native guide. Its summary, story, sight notes, plan-your-visit, chronology, safety notes and regulations are written for Unigrids in `Pipeline/content/guides/`, checked against the NPS Data API and the park's Wikipedia article; facts that could not be confirmed were left out.
- Panels added to the list above: a **gallery** of up to three more public-domain NPS photographs, **entrance fees** and **operating hours** inside Plan your visit, **weather and seasons** and **getting there** (both the NPS's own text, credited), and **live alerts** when the build has an NPS key.
- The map panel is an Apple map with the park's outline and numbered sights, with an **Explore in 3D** view that flies between them; the official brochure map is not used yet.
- Panels in a row of the grid share a height.
- The official brochure viewer is not built.
- Places in tiers 2–4 get a leaflet page — photograph, overview, outline map and actions — rather than a guide.

## 7. 3D park exploration

Zooming into a national park (or tapping Explore in 3D) flies the camera to the park in Apple Maps 3D, with Unigrids layers drawn on top. Apple's terrain and imagery do the heavy lifting; the app adds the park's structure.

What the 3D view shows

- Realistic-elevation terrain with satellite or hybrid imagery; the user can switch to the standard map style.
- Park boundary as a tinted outline.
- Major sights as numbered pins, ranked to match the guide.
- Visitor centres with a distinct icon; entrances and viewpoints as smaller pins.
- Trails as optional polylines from the trail catalogue.

Interactions

- Pitch, rotate and zoom freely; a reset button returns to the park overview.
- Tapping a sight flies the camera to it and opens its card (photo, description, check in).
- Guided fly-through: a preset camera path that visits the major sights in order, pausing at each.
- iPad and Mac: a sidebar lists sights; selecting one moves the camera, and panning updates the list.

Limits to design around

- 3D detail and imagery quality vary by area and are outside the app's control.
- Apple's base map cannot be restyled to look like an NPS map; the NPS look lives in the guide and offline maps instead.
- 3D needs a connection; offline users fall back to the downloaded park map (section 8).

## 8. Trails and offline park maps

Every national park gets a trail catalogue built from the NPS public trails dataset, and an offline pack bundled with the app so the map and trails work without signal. Live GPS recording and workout import are out of scope for now.

Trail catalogue

- Source: the [NPS Public Trails dataset](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0), a nationwide, public-release subset of official visitor-use trails maintained by park GIS staff; OpenStreetMap fills gaps in names or connectors where needed.
- Per trail: route line, length, elevation gain and loss, elevation profile, highest and lowest point, estimated time, difficulty, route type (loop, out-and-back, point-to-point), trailhead, sights along the way, seasonal notes, dogs and bikes allowed.
- Length, elevation and profile are computed in the pipeline from the route line and USGS elevation data, so every trail is measured the same way.
- Filters: length, gain, difficulty, route type, features (waterfall, summit, lake, arch, beach).
- Mark as hiked (full or partial, with date): feeds the log and the trail stats.

Offline park packs

- One pack per national park and per busy state park (a curated list), bundled with the app.
- Contents: topo-style map tiles for the park extent, trails, sights, visitor centres, guide content and the brochure PDF.
- Tiles are rendered by the pipeline from USGS elevation and hillshade, OpenStreetMap roads and water, and NPS trails, styled to echo NPS cartography.
- Shown inside MapKit as an app-supplied tile layer; the user's location dot works offline, with no routing.
- Packs update with app releases; there are no separate downloads.
- Pack size targets come from the pilot; packs and the database together must fit the App Store's 4 GB app limit.

## 9. Trip logging and the passport

A visit can enter the log four ways, and every route ends in the same structure: a trip holds park visits, and each visit holds check-ins at sights, visitor centres and trails. Nothing is logged without the user confirming it.

Ways to log

- Manual check-in: from a map card, guide panel or trail page. Fields: date and time, notes, rating, and linked photos (stored as Photos library references plus a small thumbnail, not copies).
- Auto-detected visits: with Always location permission, the app watches the boundaries of the parks nearest the user and suggests a visit on entry ("Looks like you're in Zion. Log a visit?"). iOS limits how many regions an app can monitor at once, so the watched set rotates as the user moves. Processing stays on device.
- Photo import: an on-device scan of geotagged photos that fall inside park boundaries, grouped by date into proposed visits and trips for the user to accept, edit or discard. Works with limited Photos access by scanning only the selected photos.
- Trail hikes: marking a trail as hiked creates a check-in on that visit.

Passport

The Passport tab is a digital stamp book in the style of the paper NPS passport: the user stamps each place they have been, with the date, and the book fills up region by region.

> _Diagram in source doc: passport page mock-up · 6 slots, 2 with the America 250 seal_

Organisation

- Nine colour-coded regions, as in the paper passport: North Atlantic, Mid-Atlantic, National Capital, Southeast, Midwest, Southwest, Rocky Mountain, Western, and Pacific Northwest and Alaska ([AAA Northeast](https://magazine.northeast.aaa.com/?p=30554)). Each region stamps in its own ink colour, as the paper cancellations do ([Kidventurous](https://kidventurous.com/?p=678)).
- NPS sites follow the paper passport's region assignments, curated once in the pipeline; state parks and federal sites go by their state. Each region opens with a title page: a small map of its sites and a stamped-so-far count.
- Site pages follow, with a labelled slot for every NPS site in the region; empty slots stay as faint outlines so the gaps show what is left.
- After the NPS pages, a Beyond the NPS section per region holds state parks and federal sites, filled in the order they are stamped.
- A site with several official stamp locations (several visitor centres, say) gets one slot per location; the slot shows the latest impression and opens to all of them.

Stamping

- Tap an empty slot, or Stamp on a map card, guide or check-in. A stamp sheet asks for the date (today or the visit date by default) and, where relevant, the stamp location; press and hold to stamp.
- The stamp lands with a haptic thump and a short ink animation. Each impression gets a slight tilt, offset and ink density, fixed by a stored seed so it looks the same every time.
- Stamp face: cancellation style, with the site name at the top, the date across the centre and the state at the bottom, in the region's ink.
- Stamping creates or joins a visit in the log, so the passport and the trip log always agree. A later visit adds a new impression that overlaps the old one, like a well-used paper page.
- Stamping is free-form: any place, any date, including back-dated stamps for past trips, and photo import offers to stamp the visits it finds. A stamp made on site (confirmed by location) gets a small verified tick.
- A real-stamp-collected toggle on each impression helps paper-passport collectors see which cancellations they still need.

America 250

- Every stamp dated in calendar year 2026 (1 January to 31 December), the 250th anniversary year of 1776, gets an America 250 overprint: a red seal reading AMERICA 250, stamped across the corner of the regular impression.
- The rule follows the stamp's date, not when it was entered, so 2026 visits logged later still get the seal.
- A 2026 commemorative page at the front of the passport gathers every 2026 stamp, with the year's count.

Views

- iPhone: one page at a time, swipe to turn; pinch out for a grid of all regions.
- iPad and Mac: a two-page spread, like an open passport.
- Any page or spread exports as an image for sharing.

Ownership of data

- Edit or delete anything; undo for deletions.
- Export the full log as JSON and CSV, trips as GPX of visited points.
- Share cards: an image of a visit, trip or stamp page for Messages or social apps.

## 10. Planner

Planned trips use the same trip object as the log: a trip starts as a plan, becomes active on its first day, and turns into a logged trip as the user checks in. The planner adds four tools on top.

As built for the MVP (`0.2.0`): trips with ordered stops (places, not yet sights or lodging), a planned date per stop, reordering, a route map with the straight-line distance, an `.ics` export of dated stops, and "Add to trip" from every place. Planned places show dashed on the map. Drive times, conflict flags, reminders, forecasts and the weather-versus-crowds view are not built; live alerts appear in guides only.

Trip itineraries

- Multi-day, multi-park trips; each day holds ordered stops (sights, trails, visitor centres, lodging, custom points).
- Drive times between stops from MapKit directions; a day total and a warning when a day looks overloaded.
- Conflict flags: a stop inside an active closure alert, a seasonal road closure, or a day missing a required timed-entry reservation.
- Export to Apple Calendar or as an .ics file.

Live park alerts

- Pulled directly from the NPS API alerts feed, which carries danger, closure, caution and information alerts per park.
- Shown on the map, in the guide's Plan your visit panel, and on the trip.
- Background refresh for parks on upcoming trips; a notification when a new danger or closure alert appears.

Permits and timed entry

- Per park: what needs a reservation or permit (entry, popular trails, backcountry, campgrounds), curated in the pipeline because rules change each season.
- Reminders: the user sets when a booking window opens or when their entry slot is, and gets local notifications ahead of it.
- Booking itself happens on Recreation.gov via deep link; Unigrids never handles payments or accounts.

Weather and seasons

- WeatherKit forecast for each park on the trip, including sunrise and sunset.
- Best time to visit: monthly climate normals (precomputed from the Open-Meteo/ERA5 archive) alongside monthly NPS visitation, giving a weather-versus-crowds view per month.
- Seasonal notes: roads and facilities that close in winter, peak wildflower or foliage windows where the NPS publishes them.

## 11. Stats

Stats turn the log into four families of insight, each a scrollable page of charts and headline numbers, all computed on device from the log plus bundled reference data.

| Family | Examples | Built from |
|---|---|---|
| Completion and coverage | 23 of 63 national parks; NPS units visited; states and regions with a visit; a US map that fills in; nearest unvisited park | Visits + place list |
| Weather and season | Hottest, coldest and wettest visit; visits by season and month; snow days; "fair-weather visitor or storm chaser" | Weather snapshot per visit (WeatherKit for recent dates, Open-Meteo archive for older ones) |
| Themes and landscapes | Share of visits by geology (canyons, volcanoes, glaciers, caves, dunes), ecosystem (desert, alpine, rainforest, reef) and history era; "4 of 6 volcanic parks seen" | Theme tags per park, curated in the pipeline and seeded from NPS API topics and activities |
| Trail and elevation | Distance hiked; elevation gained; highest and lowest points reached; longest hike; gain expressed in Everests | Hiked trails + catalogue measurements |

Presentation

- Swift Charts in the native app style (not Unigrid), with a headline number on each card.
- Every stat card can become a share card.
- Later: a year-in-review page, first and latest visit, and streaks.

Weather for each visit is fetched once when the visit is logged (or imported) and stored, so stats never depend on a live call.

## 12. Data sources and content pipeline

Almost everything comes from free US government data, joined and cleaned by an offline Python pipeline; only alerts and weather are fetched live by the app.

| Source | Used for | Access and terms |
|---|---|---|
| [NPS API](https://www.nps.gov/subjects/developer/changelog.htm) | Park list, descriptions, fees, hours, visitor centres, places, things to do, campgrounds, stamp locations, live alerts | Free key; rate-limited per key |
| [NPS brochure maps (Harpers Ferry Center)](https://npgallery.nps.gov/AssetDetail/939b95c9-0c09-4c20-8c65-c1be52c78754) | Guide map panel, brochure viewer | Maps are public domain and may be modified; no NPS seal or implied endorsement |
| [NPS Public Trails](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0) | Trail lines for all NPS units | Public NPS dataset (ArcGIS service) |
| [PAD-US 4.1 (USGS)](https://www.sciencebase.gov/catalog/item/6759abcfd34edfeb8710a004) | Boundaries and designations for state parks (patched from state agency data where thin), national forests, BLM units, wildlife refuges | Free download, national or per state; state completeness varies |
| [RIDB / Recreation.gov](https://catalog.data.gov/dataset/recreation-information-database-ridb-58364) | Facilities, campgrounds, permit entrances, deep links for booking | Free key; Creative Commons Attribution |
| USGS elevation (3DEP) | Trail profiles, hillshade for offline tiles | Public domain |
| OpenStreetMap | Roads, water and labels for offline tiles; trail gap-filling | ODbL: attribution, and share-alike for derived databases |
| WeatherKit | Forecasts, sunrise and sunset, recent weather | Included with the developer account; Apple attribution required |
| [Open-Meteo archive](https://open-meteo.com/) | Weather for older visits; monthly climate normals | ERA5 reanalysis from 1940; free for non-commercial use, data under CC BY 4.0 |
| National natural landmarks, scenic byways | Tier 4 pins and lines | Official lists: every National Natural Landmark, and nationally designated scenic byways and All-American Roads; data files still to be located |

Pipeline steps

1. Fetch: pull each source into a raw store, versioned by date.
2. Match: give every place, sight and trail a stable Unigrids ID, mapped to NPS park codes and PAD-US unit IDs, so user logs survive data updates.
3. Derive: trail length, elevation and profile; theme tags; passport region for every site; climate normals; sight rankings.
4. Edit: guide text and curated fields (permits, seasonal notes) kept in plain files under version control.
5. Build: the bundled SQLite database and one offline pack per national park.
6. Package: copy the database and packs into the app's resources for the next release, and re-check every brochure link (NPS links are not standardised across parks and can move).

Live calls: the app calls the NPS API directly with a key built into the app, plus WeatherKit and Open-Meteo for weather. There is no proxy or server. A built-in key can be extracted and its rate limit is shared by every user; that is acceptable for a private hobby app and worth revisiting if Unigrids goes public.

As built for the MVP (`0.2.0`): `unigrids_pipeline reference` fetches the NPS Data API (parks, visitor centres, stamp locations, places, campgrounds), the NPS Land Resources Division unit boundaries, PAD-US 4.1 (fee and management layers), Wikipedia summaries and Wikimedia Commons licence metadata, versioned by date under `Pipeline/raw/`, and builds the bundled JSON (`manifest`, `places`, `pois`, `themes`, `boundaries`, `guides/`) and photographs. National park photographs are NPS public-domain images only; photographs of other places come from Wikimedia Commons under a reusable licence and carry it. The key for live alerts reaches the app through a gitignored `Secrets.plist` (`AGENTS.md` §5).

## 13. Core data model

Reference data and user data live in separate stores: reference data is read-only and replaced on update, while user data syncs through iCloud and only ever points at reference records by stable ID.

| Entity | Key fields | Store |
|---|---|---|
| Place | id, name, kind (national park, NPS unit, state park, forest, BLM, refuge, landmark, byway), tier, agency, states, centre, boundary, NPS park code, PAD-US id, passport region, themes | Reference |
| PointOfInterest | id, place id, kind (sight, visitor centre, viewpoint, entrance, trailhead, stamp location), name, location, rank, description | Reference |
| Trail | id, place id, name, geometry, length, gain, loss, high and low point, difficulty, route type, features | Reference |
| GuideContent | place id, structured panels, credits, content version | Reference |
| Brochure | place id, edition, source URL, size, cache path | Reference |
| Theme | id, family (geology, ecosystem, history), name | Reference |
| Trip | id, name, start and end, status (planned, active, done), notes | User |
| ItineraryStop | trip id, day, order, target (place, sight, trail or custom point), planned time | User |
| Visit | id, trip id (optional), place id, dates, source (manual, auto, photo), rating, notes | User |
| CheckIn | id, visit id, sight or trail id, time, photo references | User |
| Hike | id, visit id, trail id, date, full or partial | User |
| Stamp | id, place or stamp-location id, visit id, date, impression seed (tilt, offset, ink), verified on site, real stamp collected; America 250 seal derived from the date | User |
| Reminder | id, trip id, kind (permit, timed entry, booking window), date, link | User |
| WeatherSnapshot | visit id, date, high, low, precipitation, condition, source | User |

## 14. Design language

The app has one identity: the Unigrid brochure, carried through every screen and laid over native Apple structure, so the app feels at home on each device and still reads as one product. The guides keep the full panel grid; the map, directory, trips, passport, stats and settings open with the black band and use the same ruled heads, square controls, figures and place markers ([ADR 0007](docs/adr/0007-one-identity-across-every-screen.md), which replaced an earlier split into a Unigrid mode for guides and a stock native mode for everything else).

The Unigrid reference

- Designed by Massimo Vignelli's office for the NPS in 1977 ([Vignelli Center](https://artsandculture.google.com/asset/edison/lgFwy0lDWgS_pA)): a modular system of fold panels about 4 by 8¼ inches, a black title band across the top, and Helvetica with Times Roman as the original typefaces ([overview](https://blakecrosley.com/blog/design-philosophy-massimo-vignelli)).

Guide rules for Unigrids

- Black title band with the park name in white, set in a neo-grotesque sans (Helvetica Neue ships on Apple platforms).
- Grid columns derived from the panel module: one on iPhone, two or three on iPad, three or four on Mac.
- Sans for headings and data; a serif for longer passages, echoing the original pairing.
- Photos and maps sit on the grid, often full column width; colour fields used sparingly to group panels.
- Map panels use the NPS cartographic palette from the brochure maps.
- A dark variant of the guide that keeps the band and grid but inverts the page.

Themes and appearance

- Four palettes, selectable in Settings: Unigrid (the canonical warm stock and park green), Press (near-monochrome ink on paper), Canyon (sandstone and ochre) and Tidewater (the brochure blues). A palette changes the paper, ink, band and app tint on every screen; system controls keep their semantic colours.
- Appearance is a separate axis: Dark (the default), Light or Automatic. Both choices are per-device display preferences stored in `UserDefaults`, not user data, and do not sync through iCloud.
- The band stays near-black in every palette. A black title band with the park name reversed out of it is the one part of the Unigrid that is not ours to restyle.
- A place's tier is a shape — square for a national park, small square for another NPS site, circle for a state park, diamond for a monument or refuge — and its agency an ink, wherever the place appears. Filled is visited; dashed is planned.
- Colour values and the WCAG contrast rule live in `UnigridsCore` as plain data, so every palette, scheme and foreground/background pairing is held to WCAG AA by a test rather than by eye. See [`docs/design-system.md`](docs/design-system.md) and [ADR 0005](docs/adr/0005-palette-and-appearance.md).

App identity

- Name: Unigrids. Icon: an original mark (for example, a black band over a grid of panels), never the NPS arrowhead.
- A clear "not affiliated with the National Park Service" line in onboarding and About.

Accessibility

- Guides reflow with Dynamic Type; the grid collapses to fewer columns rather than shrinking text.
- VoiceOver labels for every pin, panel and chart; contrast checked in both light and dark.

## 15. Privacy, legal and licensing

Unigrids aims for an App Store privacy label of "Data Not Collected": no accounts, no analytics SDKs, no ads, and location and photo processing on device only. The only outbound requests are park codes and coordinates sent to data and weather services, plus brochure downloads from NPS.

Privacy

- Location: used only for auto-detected visits, the verified stamp tick and the on-map dot; never uploaded or stored as a track.
- Photos: scanned on device; the app stores asset references and thumbnails, not originals.
- Sync: the user's own iCloud private database; the developer cannot read it.
- No proxy or server of any kind, so the developer never holds user data.

Intellectual property and naming (parked while Unigrids is private; revisit before any public release)

| Item | Constraint | What Unigrids does |
|---|---|---|
| NPS brochure maps | Public domain; may be modified; no NPS seal or claimed endorsement ([NPGallery](https://npgallery.nps.gov/AssetDetail/939b95c9-0c09-4c20-8c65-c1be52c78754)) | Uses and restyles them freely, with a source credit |
| NPS arrowhead | Registered trademark; use needs the NPS Director's written permission ([NPS disclaimer](https://www.nps.gov/aboutus/disclaimer.htm)) | Never used, in the app or the icon |
| Photos and art inside NPS publications | Some NPS content carries third-party rights ([NPS disclaimer](https://www.nps.gov/aboutus/disclaimer.htm)) | Brochures shown as published with credits; only photos confirmed public domain are reused in native guides |
| Passport programme and stamp designs | Owned, with copyright and trademark, by Eastern National / America's National Parks ([Passport FAQ](https://americasnationalparks.org/?p=64)) | Mirrors the paper passport's nine regions, ink colours and cancellation format while the project is private |
| "Unigrid" and the app name | The Unigrid is an NPS design programme; an official-looking app could read as government-affiliated | Trademark search before release; disclaimer of non-affiliation; distinct icon |
| Open data licences | OSM (ODbL), Open-Meteo (CC BY 4.0), RIDB (CC BY), WeatherKit attribution | An Attributions screen, plus map attribution where tiles show |

Safety: trail and map information is for planning, not wilderness navigation; guides point users to current conditions and ranger advice. This section is a working checklist, not legal advice; a short review before App Store submission is worthwhile.

## 16. Phasing

The build goes in three phases: a pilot on four parks (Zion, Acadia, Yellowstone, Great Smoky Mountains) to prove the pipeline and the guide template, an MVP with every national park guide and basic logging, then v1.0 adding trails, offline maps, the planner, widgets, the Watch app and the remaining logging and stats. No dates are set yet.

> _Diagram in source doc: phasing · 3 phases, 2 gates, then a backlog_

The pilot is the riskiest step: it tests whether one Unigrid template reflows well across three devices and how large an offline pack really is, and so whether everything fits in the 4 GB app limit, and both answers shape everything after it.

## 17. Open questions for the next round

All questions from the second round are answered and folded into section 2. What remains are follow-ups those answers created, plus items parked until a public release.

Follow-ups

1. Pick the busy state parks that get offline packs.
2. Measure the pilot packs, then confirm the whole bundle fits in 4 GB; if not, decide what to trim (tile zoom levels, state packs).
3. Compile the paper passport's region assignments for NPS sites (a one-time curation).
4. Locate data files for National Natural Landmarks and for designated scenic byways and All-American Roads.
5. Scope the Apple Watch app: check-ins and stamps only, or also trail info and alerts?
6. Choose which widgets to build first (next trip, parks count, latest stamp).
7. The passport's nine ink colours are Unigrids' own approximation, now with a dark variant per region. They are superseded by follow-up 3 above when the paper passport's real scheme is curated.
8. Appearance is two `@AppStorage` values today. An observable store becomes worth it only if the palette is ever derived from something else — a per-park palette, or an automatic switch at sunset (ADR 0005).
9. The written guide and overview text (63 guides, 101 place summaries) was drafted from the NPS Data API and Wikipedia and checked fact by fact, but has had no second reader. A park-by-park read against each park's NPS pages before a public release is worthwhile; rules that change each season (timed entry, permits, closures) are written to say "check before you go" rather than give dates.
10. Grand Staircase–Escalante's boundaries were redrawn by proclamation in July 2026. Its outline comes from PAD-US 4.1, which predates that, so the map shows the earlier boundary until PAD-US catches up.
11. The iOS 27 Simulator runtime is not installed on the development Mac, so iPhone and iPad layouts were built and compiled but checked only on macOS. A pass on an iOS 27 device or simulator is the first thing to do before sharing a TestFlight build.
12. Reference data is a snapshot (`Pipeline/raw/2026-10-19`). Fees, hours and visitor-centre details go stale; a re-fetch before each release (`reference --refresh`) keeps them current.
13. NPS units whose API record has no description yet (Freedom Riders and Emmett Till and Mamie Till-Mobley, both recent) show no summary rather than an invented one.

Parked until a public release

1. Intellectual property and naming (section 15), including a trademark search on "Unigrids".
2. Open-Meteo terms: free use is limited to non-commercial apps.
3. NPS key built into the app: move it behind a proxy if usage grows.

## Sources

- [WorldAtlas: states with a national park (63 parks, Aug 2026)](https://www.worldatlas.com/national-parks/how-many-states-have-a-national-park.html)
- [Citizen Daily Post: 433 NPS units (Jul 2026)](https://www.citizendailypost.com/faq/how-many-national-parks-are-in-the-us/)
- [Apple Developer Forums: offline maps in MapKit](https://developer.apple.com/forums/thread/765857)
- [Apple WWDC24: Bring context to today's weather (WeatherKit)](https://developer.apple.com/fr/videos/play/wwdc2024/10067/)
- [NPS API changelog](https://www.nps.gov/subjects/developer/changelog.htm)
- [NPGallery: NPS map public-domain terms](https://npgallery.nps.gov/AssetDetail/939b95c9-0c09-4c20-8c65-c1be52c78754)
- [NPS Public Trails dataset](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0)
- [PAD-US 4.1 state downloads (USGS)](https://www.sciencebase.gov/catalog/item/6759abcfd34edfeb8710a004)
- [RIDB on data.gov](https://catalog.data.gov/dataset/recreation-information-database-ridb-58364)
- [Open-Meteo](https://open-meteo.com/)
- [NPS website disclaimer (arrowhead, third-party rights)](https://www.nps.gov/aboutus/disclaimer.htm)
- [America's National Parks: Passport FAQ](https://americasnationalparks.org/?p=64)
- [Vignelli Center: Unigrid brochure, 1977 programme](https://artsandculture.google.com/asset/edison/lgFwy0lDWgS_pA)
- [Design Philosophy: Massimo Vignelli (Unigrid overview)](https://blakecrosley.com/blog/design-philosophy-massimo-vignelli)
