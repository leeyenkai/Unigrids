# Sources for New Zealand, Australia and Canada

What 0.11.0 actually uses, written on **2026-11-18** from the code that uses it: the
pipeline's `SourceTerms` (`Pipeline/src/unigrids_pipeline/countries/{nz,ca,au}/fetching.py`,
`countries/abroad/`, `sources/osm_pbf.py`), the app's live-warning clients
(`Packages/UnigridsKit/Sources/UnigridsFeatures/Alerts*.swift`) and its Attributions
(`Attributions.swift`). Unlike [`sources-japan-norway.md`](sources-japan-norway.md), this is
not a check made before the build; it records what the build settled on. Licences and
credit lines are quoted as the code states them. Where the code names no licence, the row
says so rather than supply one.

This file feeds `NOTICE.md` and the Attributions screen; the decisions behind it are
[ADR 0014](adr/0014-six-countries.md) and `SPECIFICATION.md` §17, items 27–36.

## How to read it

- **Verdicts.** **USE**: used as published. **USE WITH CONDITIONS**: used, and the note
  matters. **NOT USED**: looked at in building and left out, with the reason.
- **Tables**: New Zealand (Z), Canada (C), Australia (A), the sources all three share (S),
  and the live services the app calls itself (L). Each row's number is what the notes
  refer to.
- Every fetch lands in `Pipeline/raw/<date>/<source>/` with a `source.json` holding the
  terms below. Requests identify the app and nothing else, and pause between calls.

## New Zealand

| # | Source | URL | Licence | Credit line | Verdict |
|---|---|---|---|---|---|
| Z1 | **DOC Public Conservation Land** (NaPALIS): the 13 national parks (`S4_NATIONAL_PARK`) and every conservation and forest park (`S19_CONSERVATION_PARK`) | `https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services/DOC_Public_Conservation_Land_FHV/FeatureServer/0` | CC BY 4.0 | "Crown Copyright: Department of Conservation Te Papa Atawhai" | **USE WITH CONDITIONS** (Z-1) |
| Z2 | **DOC Tracks** (`DOC_Tracks_Open_Data`), the whole layer | `…/DOC_Tracks_Open_Data/FeatureServer/0` | CC BY 4.0 | as Z1 | **USE WITH CONDITIONS** (Z-2) |
| Z3 | **DOC huts, campsites and visitor centres**: the asset layers (`DOC_Huts_Open_Data`, `DOC_Campsites_Open_Data`, `DOC_Vistor_Centres_DTO`) and the website layers beside them (`DOC_Huts`, `DOC_Campsites`) | `https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services` | CC BY 4.0 | as Z1 | **USE** (Z-3) |
| Z4 | **Stats NZ regional councils**, as Eagle Technology hosts them | `https://services.arcgis.com/XTtANUDT8Va4DLwI/arcgis/rest/services/nz_regional_councils/FeatureServer/0` | CC BY 4.0 | "Contains data sourced from Stats NZ licensed for reuse under CC BY 4.0" | **USE** (to say which regions a place lies in) |
| Z5 | **DOC national park pages** and the PDFs they link | `https://www.doc.govt.nz/parks-and-recreation/places-to-go/national-parks/` | Crown copyright; links only, nothing extracted | as Z1 | **USE** (linked; each PDF checked with HEAD) |
| Z6 | **DOC's track categories** page, the grade's definition | `https://www.doc.govt.nz/parks-and-recreation/things-to-do/walking-and-tramping/track-categories/` | — | named as the grade's publisher | **USE** (the six category names; the page is linked from each grade) |

### New Zealand: notes

- **Z-1.** Te Urewera is not in the layer: since the Te Urewera Act 2014 it is not
  conservation land. A conservation park record under **5 km²** is left out — DOC records
  access strips and outlying parcels as parks of their own ("Wires Road Access", 800 m²) —
  which leaves 49; the build lists what it drops. A record named "Conservation Park – …"
  is a parcel of the park it names. A park's area is its guide's; where a guide gives none
  (Taranaki, Westland) DOC's `Recorded_Area` stands in, never the outline's measured area.
  Westland's record names it "Westland National Park/Tai Poutini National Park", which is
  where its te reo name comes from.
- **Z-2.** Most geometry is DOC's own generated line. The build keeps open, public walking
  tracks (not cycle tracks or pavement): 610 in the 13 parks. The layer still carries old
  labels ("Great Walk/Easy tramping track", "Route"), mapped to the six current
  categories; 605 tracks carry one. Names keep DOC's wording, with the asset prefix ("T3:")
  removed and "Tk" spelled out; nothing else is expanded. A track whose sections cross from
  one park to another (the Routeburn) stays with the park it was first listed in.
- **Z-3.** The asset layers decide what is open and in public use; the website layers,
  joined on the asset number, give each hut's and campsite's page and booking: 258 huts and
  78 campsites. Most visitor centres come from the guides (11 of 12).

## Canada

| # | Source | URL | Licence | Credit line | Verdict |
|---|---|---|---|---|---|
| C1 | **Canadian Protected and Conserved Areas Database** (CPCAD, Environment and Climate Change Canada): national parks, national marine conservation areas, provincial and territorial parks | `https://maps-cartes.ec.gc.ca/arcgis/rest/services/CWS_SCF/CPCAD/MapServer/0` | Open Government Licence – Canada | "Contains information licensed under the Open Government Licence – Canada (Environment and Climate Change Canada, Canadian Protected and Conserved Areas Database)" | **USE WITH CONDITIONS** (C-1) |
| C2 | **Parks Canada trails** (Trails APCA, the open layer of the 2025 migration) | `https://services2.arcgis.com/wCOMu5IS7YdSyPNx/arcgis/rest/services/Trails_Sentiers_APCA_Temporary_Temporaire_APCA_OpenOuvert/FeatureServer/0`; record `https://open.canada.ca/data/en/dataset/64a90e8d-5bc0-4027-8645-b5881b4068d4` | Open Government Licence – Canada | "Contains information licensed under the Open Government Licence – Canada (Parks Canada)" | **USE WITH CONDITIONS** (C-2) |
| C3 | **Parks Canada facilities and accommodation** | `…/Facilities_Installations_Point_OpenData/FeatureServer/0`, `…/Accommodation_Hebergement_APCA_OpenOuvert/FeatureServer/0`; records `https://open.canada.ca/data/en/dataset/3969368d-33b5-47c8-8953-f31b15d8e007`, `…/74054d44-68cf-41af-8919-5f09f80dcd02` | Open Government Licence – Canada | as C2 | **USE** (335 campgrounds, 17 huts, 8 visitor centres; the guides give the other 40) |
| C4 | **Parks Canada attendance 2025-26** | `https://open.canada.ca/data/en/dataset/1e2bd6b2-d6c7-415b-8c95-f5f6b2459759` | Open Government Licence – Canada | as C2 | **USE WITH CONDITIONS** (C-3) |
| C5 | **Parks Canada park pages** and the PDFs they link | `https://parks.canada.ca/pn-np` | Crown copyright; links only, nothing extracted | "Parks Canada" | **USE** (each park's page, its "Plan your visit" page and the brochure and map pages it links; each PDF checked with HEAD) |
| C6 | **Parks Canada's park list** | `https://parks.canada.ca/pn-np` (checked 18 November 2026) | — | — | **USE** (C-4) |

### Canada: notes

- **C-1.** A national park is every CPCAD record under its `PARENT_ID` with a park
  designation, joined to Parks Canada's list by that parent. Geometry is generalised by
  the service (about 10 m for the national parks, 50 m for the rest) and simplified by
  Unigrids. A provincial or territorial park is kept at **100 km²** or more by CPCAD's
  official area (`O_AREA_HA`): 254, Québec's *parcs nationaux* among them, labelled
  provincial whatever their name. A national park's area is its guide's, from Parks
  Canada; Mingan Archipelago (Parks Canada "approximately 100 km²", CPCAD 150.7), Bruce
  Peninsula (enlarged by purchase since its scheduled area) and Thousand Islands (no Parks
  Canada figure) carry none.
- **C-2.** The layer has no park field and no trail identifier, and repeats a line once
  per activity; the build keeps named hiking records inside a national park and joins
  them by name. Summer difficulty — Easy, Moderate, Difficult, Most difficult — travels
  with a trail only when every hiking record of it agrees. In this build the layer gives
  7 parks their trails (498, 425 rated); parks it leaves without any take OpenStreetMap's
  (S2).
- **C-3.** Counts are for Parks Canada's fiscal year, 1 April 2025 to 31 March 2026, and
  are labelled so. "UR" (under review) is not a count. Mount Revelstoke and Glacier are
  counted together and carry no figure; seven parks have no row; 38 of 48 carry one.
- **C-4.** Canada's 48 are the page's 47 national parks and national park reserves and
  Rouge National Urban Park. Pituamkek, an interim reserve in CPCAD that the page does not
  list, is left out. French names are those of the French pages (`parcs.canada.ca/pn-np`).

## Australia

| # | Source | URL | Licence | Credit line | Verdict |
|---|---|---|---|---|---|
| A1 | **Collaborative Australian Protected Areas Database (CAPAD) 2024**, terrestrial (DCCEEW): every record of the 51 guided parks and every record typed "National Park" | `https://gis.environment.gov.au/gispubmap/rest/services/ogc_services/CAPAD/MapServer/0`; dataset `https://fed.dcceew.gov.au/datasets/erin::collaborative-australian-protected-areas-database-capad-2024-terrestrial` | CC BY 4.0 | "© Commonwealth of Australia (Department of Climate Change, Energy, the Environment and Water), Collaborative Australian Protected Areas Database (CAPAD) 2024, CC BY 4.0" | **USE WITH CONDITIONS** (A-1) |
| A2 | **ABS ASGS Edition 3 (2021): States and Territories** | `https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/STE/MapServer/0` | CC BY 4.0 | "Australian Bureau of Statistics, Australian Statistical Geography Standard (ASGS) Edition 3, CC BY 4.0" | **USE** (A-2) |
| A3 | **Queensland Parks and Wildlife Service access: walking tracks** (QSpatial `ParksTerrestrialProtectedAreas`, layer 5) | `https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Environment/ParksTerrestrialProtectedAreas/MapServer/5`; record `https://www.data.qld.gov.au/dataset/queensland-parks-and-wildlife-service-access` | CC BY 4.0 | "© State of Queensland (Department of the Environment, Tourism, Science and Innovation), CC BY 4.0" | **USE WITH CONDITIONS** (A-3) |
| A4 | **The parks' own pages** — Parks Australia and the state and territory agencies — and the PDFs they link | `https://parksaustralia.gov.au/`, `nationalparks.nsw.gov.au`, `parks.act.gov.au`, `parks.vic.gov.au`, `greatoceanroadauthority.vic.gov.au`, `parks.qld.gov.au`, `parks.sa.gov.au`, `exploreparks.dbca.wa.gov.au`, `parks.tas.gov.au`, `nt.gov.au/parks` | Crown copyright; links only, nothing extracted | "Parks Australia and the state and territory park agencies" | **USE** (as each guide's sources give the page; each PDF checked with HEAD) |
| A5 | **NSW NPWS walking tracks** | — | — | — | **NOT USED**: the layer needs a token. Victoria, South Australia, Western Australia, Tasmania and the Northern Territory publish no open track grades a fetch can read without a key, so their parks' trails are OpenStreetMap's, with the estimate |

### Australia: notes

- **A-1.** Data current at 30 June 2024. A park is every record of its CAPAD names in its
  own state with a national park designation, its parcels merged; geometry generalised by
  the service (about 10 m for guided parks, 50 m for the rest) and simplified by Unigrids.
  Names drop Queensland's tenure note ("(Limited Depth)"); records named only by number
  ("Unnamed WA17519") are left out. `AUTHORITY` gives the managing agency
  (`managedBy`); Victoria's records name the department, which is kept, since not every
  Victorian park is Parks Victoria's. **Years**: CAPAD's `GAZ_DATE` is when the land was
  last gazetted; it disagreed with the agency's founding year for 11 of 44 guided parks, so
  a park's year is its guide's alone, and seven show none. **Areas**: a guided park's is its
  guide's (Kakadu, Naracoorte Caves and Nitmiluk carry none: the sources disagree). A
  second-tier park takes the gazetted area (`GAZ_AREA`) where every record gives one and
  the total agrees with the mapped area (`GIS_AREA`) to within 25 %, else the mapped area.
  The Northern Territory repeats a park's whole gazetted area on each parcel, counted once;
  Tasmania and the ACT record none.
- **A-2.** Generalised by the service to about 100 m and used only to say where a place
  lies. Code 9, "Other Territories", is split by location into Jervis Bay, Christmas
  Island, the Cocos (Keeling) Islands and Norfolk Island.
- **A-3.** Read whole. A trail is the open, named records of one name inside a park, joined
  where they lie together. The grade is the pedestrian class, "Track class 3 to AS 2156.1",
  which the Australian Walking Track Grading System's five grades are built on; it travels
  with a trail only when every classed record agrees. 240 tracks in 9 parks, 192 graded.

## All three countries

| # | Source | URL | Licence | Credit line | Verdict |
|---|---|---|---|---|---|
| S1 | **OpenStreetMap, from Geofabrik's extracts**: New Zealand's and Australia's whole extracts, Canada's thirteen provincial and territorial ones read in turn and deleted once read | `https://download.geofabrik.de/australia-oceania/new-zealand-latest.osm.pbf`, `…/australia-latest.osm.pbf`, `https://download.geofabrik.de/north-america/canada/<province>-latest.osm.pbf` | ODbL 1.0 | "© OpenStreetMap contributors" | **USE WITH CONDITIONS** (S-1) |
| S2 | **OpenStreetMap trails**: `route=hiking` relations and named `highway=path\|footway` ways touching each park's box | as S1 | ODbL 1.0 | "© OpenStreetMap contributors (ODbL)" | **USE** (Canada's parks Parks Canada's layer leaves without trails; Australia outside Queensland's tracks; never New Zealand) |
| S3 | **Wikidata**: each country's protected areas — English Wikipedia article, image (P18), Commons category | `https://query.wikidata.org/sparql` | CC0 | "Wikidata" | **USE** |
| S4 | **English Wikipedia leads** (Action API intro extracts) for the second tier | `https://en.wikipedia.org/w/api.php` | CC BY-SA 4.0 | "Summaries: Wikipedia, CC BY-SA 4.0, linked from each place" | **USE** (28 of New Zealand's 49, 188 of Canada's 259, 522 of Australia's 666 carry one) |
| S5 | **Wikimedia Commons**: licence and author metadata, and the guides' photographs (1,920 px, resized by the build) | `https://commons.wikimedia.org/w/api.php`, `https://commons.wikimedia.org/wiki/Special:FilePath/` | Per file | "Photographs credited individually, via Wikimedia Commons" | **USE** (S-2) |
| S6 | **Open-Meteo historical weather** (ERA5), daily, 2016–2025, at each park's centre | `https://archive-api.open-meteo.com/v1/archive` | CC BY 4.0; free for non-commercial use | "Weather data by Open-Meteo.com (ERA5 reanalysis), CC BY 4.0" | **USE WITH CONDITIONS** (non-commercial, `SPECIFICATION.md` §17 parked item 2) |
| S7 | **Copernicus DEM GLO-30** (cloud-optimised GeoTIFFs on AWS): trail profiles and each park's lowest and highest ground | `https://copernicus-dem-30m.s3.amazonaws.com/readme.html` | Licence for the use of the Copernicus WorldDEM-30 (free, worldwide; Art. 3–5) | "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved", with the Art. 6 liability notice | **USE** (S-3) |

### Shared: notes

- **S-1.** Used for passenger rail and stations in all three (VIA Rail in Canada; 22 lines
  in New Zealand, 13 VIA routes, 98 lines in Australia), huts in and beside Canada's parks
  (19, beside Parks Canada's 17), and Australia's campgrounds (498), huts (112) and some
  visitor centres (11). Read locally and written in Overpass's shapes; shipped as data, a
  Derivative Database under the ODbL.
- **S-2.** Every photograph keeps its credit and licence and is marked public domain only
  when its licence says so. Parks Canada's own photographs are not used, and no Australian
  agency's photographs or logos.
- **S-3.** A surface model: canopy and buildings are in the heights, so a summit reads a
  few metres low. Each park's measured extremes are kept in the raw store with a
  fingerprint of its outline, so a later build without the tiles reuses them.

## Live services the app calls

None needs a key; each request is a fixed URL, or carries a park's box or point, and
nothing about the reader.

| # | Service | URL | Licence | Credit line | Verdict |
|---|---|---|---|---|---|
| L1 | **GeoNet volcanic alert levels** (set by GNS Science) | `https://api.geonet.org.nz/volcano/val`; page `https://www.geonet.org.nz/about/volcano/val` | CC BY 3.0 NZ | "© Earth Sciences New Zealand" | **USE** (volcanoes inside a park; level 1 information, 2 caution, 3 and above danger) |
| L2 | **Environment and Climate Change Canada weather alerts**, MSC GeoMet `weather-alerts` collection | `https://api.weather.gc.ca/collections/weather-alerts/items`; page `https://weather.gc.ca/?layers=alert` | Open Government Licence – Canada | Environment and Climate Change Canada's MSC GeoMet | **USE** (alerts over the park's extent; orange or red warnings a danger, yellow and every watch a caution) |
| L3 | **Avalanche Canada** point forecasts | `https://api.avalanche.ca/forecasts/en/products/point` | not stated in the code | "Avalanche Canada, some written by Parks Canada" | **USE WITH CONDITIONS** (L-1) |
| L4 | **NSW Rural Fire Service** major incidents | `https://www.rfs.nsw.gov.au/feeds/majorIncidents.json` | not stated in the code | named in Attributions | **USE WITH CONDITIONS** (L-2; also covers the ACT's parks) |
| L5 | **Victoria's emergency feed** (Emergency Management Victoria) | `https://emergency.vic.gov.au/public/events-geojson.json` | not stated in the code | named in Attributions | **USE WITH CONDITIONS** (L-2) |
| L6 | **Queensland Fire** bushfire alerts | `https://publiccontent-gis-psba-qld-gov-au.s3.amazonaws.com/content/Feeds/BushfireCurrentIncidents/bushfireAlert.json` | not stated in the code | named in Attributions | **USE WITH CONDITIONS** (L-2) |
| L7 | **Western Australia's DFES** warnings | `https://api.emergency.wa.gov.au/v1/warnings` | not stated in the code | named in Attributions | **USE WITH CONDITIONS** (L-2) |
| L8 | **TasALERT** | `https://alert.tas.gov.au/data/data.geojson` | not stated in the code | named in Attributions | **USE WITH CONDITIONS** (L-2) |
| L9 | **NSW NPWS park alerts** (RSS) | `https://www.nationalparks.nsw.gov.au/api/rssfeed/get?type=alerts` | not stated in the code | named in Attributions | **USE** (closed parks and areas a closure; fire bans and safety alerts a caution; the rest a notice) |
| L10 | South Australia, the Northern Territory, the island territories | — | — | — | **NOT USED**: no feed a request can read. Their parks claim no live warnings rather than show an empty list |

### Live services: notes

- **L-1.** Asked only for parks in British Columbia, Alberta and Yukon, whose regions
  Avalanche Canada forecasts; danger follows the North American scale. Shown as relayed,
  with a link to the forecast.
- **L-2.** A fire inside a park or within five kilometres of its edge is the park's, at its
  Australian Warning System level: Emergency Warning a danger, Watch and Act a caution,
  Advice a notice. The feeds state no licence the code records; each is relayed as
  published, credited and linked. Worth confirming each service's terms before a public
  release (`SPECIFICATION.md` §17, parked item 1).

## Marks not used

No agency's logo or mark appears in the app, its icons, its stamps or its offline packs:
not DOC's logo or the Silver Fern, not Parks Canada's beaver symbol or wordmark, not Parks
Australia's or any state agency's logo, not Haida art. The stamp pictures are original
drawings; they show no rock art, engravings or sacred objects, and Uluṟu only whole and
distant. The non-affiliation line names DOC, Parks Canada, Parks Australia and the
Australian state and territory park agencies.
