# Notices

The MIT licence in [`LICENSE`](LICENSE) covers the Unigrids source code only. The data
bundled in the app, and the data it fetches, keeps its own terms.

## Not affiliated with any park authority

Unigrids is an independent project. It uses public-domain NPS material and public
government data, never the NPS arrowhead, and does not imply endorsement by the National
Park Service or any other agency. The same holds abroad: it is not affiliated with
Japan's Ministry of the Environment, the Norwegian Environment Agency, New Zealand's
Department of Conservation, Parks Canada, Parks Australia or the Australian state and
territory park agencies, and never uses Japan's national park mark (国立公園統一マーク),
the ministry's logo, the Norges nasjonalparker brand, DOC's logo, Parks Canada's beaver
symbol or wordmark, or any Australian park agency's logo. Offline packs abroad carry a
non-affiliation line too.

## Third-party terms

- **National Park Service** text, maps, brochures and photographs are public-domain US
  government works. Some photographs and artwork inside NPS publications carry
  third-party rights; those are shown only as published, with their credits, and never
  extracted. The 234 US national park photographs bundled under
  `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/images/` (the files
  named `np-…`) are NPS images whose credit names the NPS.
- **OpenStreetMap** data is © OpenStreetMap contributors, available under the
  [Open Database Licence](https://www.openstreetmap.org/copyright) (ODbL).
- **Open-Meteo** data is available under CC BY 4.0 and is free for non-commercial use.
- **Recreation Information Database** (RIDB) data is available under CC BY.
- **Wikimedia Commons** photographs are linked, not bundled, for US places outside the
  NPS; for the national parks abroad (742 files in all) they are bundled, resized, as the
  guides' photographs. Each is shown with its own credit and licence. Neither Parks Canada's
  nor any Australian agency's own photographs are used.
- **Apple Weather** data, once used, requires Apple's attribution.
- **Japan's Ministry of the Environment** content is used under the Public Data License
  1.0, with the source named and edits marked as Unigrids'. Photographs the ministry marks
  as another provider's are not reused.
- **Norwegian government data** (Miljødirektoratet, Kartverket, NVE) is used under the
  Norwegian Licence for Open Government Data (NLOD 2.0) or CC BY 4.0, with each source
  named.
- **New Zealand government data** (the Department of Conservation, Stats NZ) is used
  under CC BY 4.0, credited "Crown Copyright: Department of Conservation Te Papa Atawhai"
  and "Contains data sourced from Stats NZ licensed for reuse under CC BY 4.0"; GeoNet's
  data under CC BY 3.0 NZ, © Earth Sciences New Zealand.
- **Canadian government data** (Environment and Climate Change Canada, Parks Canada) is
  used under the Open Government Licence – Canada, credited "Contains information licensed
  under the Open Government Licence – Canada" with the publisher named.
- **Australian government data** (CAPAD from DCCEEW, the ABS's boundaries, Queensland's
  walking tracks) is used under CC BY 4.0, each with its publisher's credit line.
- This is a private hobby app: the owner has chosen to name every source used rather
  than leave one out for its licence. Guide prose abroad is written for Unigrids and
  never copied; the sources each guide drew on are listed in it. The stamp pictures in
  `Pipeline/content/emblems/` are original drawings made for Unigrids.

## Data sources

| Source | Used for | Terms |
|---|---|---|
| [NPS API](https://www.nps.gov/subjects/developer/) | Park list, descriptions, fees, hours, visitor centres, alerts | Free key, rate-limited |
| [NPS brochure maps](https://npgallery.nps.gov/) and each site's maps and brochures pages | Official maps and brochures viewer | Public domain; no NPS seal or implied endorsement |
| [NPS Public Trails](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0) | Trail catalogue | Public NPS dataset |
| NPS Land Resources Division | National park and NPS unit boundaries | Public domain |
| NPS National Natural Landmarks | Landmark locations | Public domain |
| US Forest Service, US Fish and Wildlife Service, BLM | National forest and grassland, wildlife refuge, BLM monument and conservation area boundaries | Public domain |
| FHWA America's Byways | Scenic byway and All-American Road routes | Public domain |
| National Transportation Atlas Database (US DOT) | Interstates, US highways, Amtrak routes and stations | Public domain |
| Census TIGERweb | State boundaries, to say which states a place lies in | Public domain |
| [PAD-US (USGS)](https://www.sciencebase.gov/catalog/item/6759abcfd34edfeb8710a004) | Boundaries for state parks | Free download |
| [Wikimedia Commons](https://commons.wikimedia.org/) | Photographs of state parks, monuments and refuges | Per photograph: public domain, CC0, CC BY or CC BY-SA, credited in the app |
| [RIDB / Recreation.gov](https://catalog.data.gov/dataset/recreation-information-database-ridb-58364) | Facilities, campgrounds, booking deep links | CC BY |
| USGS 3DEP | Trail profiles, hillshade | Public domain |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | Roads, water and labels for offline tiles | ODbL: attribution and share-alike |
| [Open-Meteo](https://open-meteo.com/) | Trip forecasts, weather for each visit, ten-year monthly climate | CC BY 4.0; free for non-commercial use |
| WeatherKit | Planned for forecasts once a development team is wired in (`SPECIFICATION.md` §17) | Apple attribution required |
| [Ministry of the Environment, Japan](https://www.env.go.jp/park/) — `nps.zip`, park lists, visitor counts | Japan's national park areas and zones, park and quasi-national park lists, annual visitors | Public Data License 1.0; source named, edits marked |
| [National Parks of Japan](https://www.japan.travel/national-parks/) | Official park pages, maps and brochures | Shown and linked as published |
| [Japan Meteorological Agency](https://www.jma.go.jp/bosai/map.html#contents=volcano) | Live eruption warnings and the volcano list, fetched by the app | Government of Japan terms; relayed unchanged and credited |
| [Miljødirektoratet — Naturvernområder](https://kart.miljodirektoratet.no/arcgis/rest/services/vern/MapServer/0) | Norway's national parks, protected landscapes and nature reserves: boundaries, names, dates, managers | NLOD 2.0, "Kilde: Miljødirektoratet" |
| [Kartverket](https://www.geonorge.no/) | Norway's counties (2024) | CC BY 4.0 |
| [Varsom / NVE](https://api.nve.no/doc/snoeskredvarsel/) | Live avalanche forecasts, fetched by the app | NLOD, credited to Varsom |
| [Natural Earth](https://www.naturalearthdata.com/) | Japan's prefectures | Public domain |
| [Wikidata](https://www.wikidata.org/) | Links from places abroad to their articles and photographs | CC0 |
| [Wikipedia](https://en.wikipedia.org/) | Overviews of places with no agency prose, adapted from each article's opening | CC BY-SA 4.0, "Summaries: Wikipedia, CC BY-SA 4.0, linked from each place" |
| [OpenStreetMap](https://www.openstreetmap.org/copyright), read from [Geofabrik](https://download.geofabrik.de/)'s extracts abroad | Japan's quasi-national park outlines; railway lines and stations in every country abroad (VIA Rail in Canada); huts in Japan, Norway and Canada; Australia's huts, campgrounds and some visitor centres; trails in Japan, in Norway where Turrutebasen has none, in Canada's parks Parks Canada's layer leaves without any, and in Australia outside Queensland's tracks; roads and water for the Park maps abroad | ODbL 1.0: "© OpenStreetMap contributors"; shipped as a Derivative Database |
| [Department of Conservation — Public Conservation Land](https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services/DOC_Public_Conservation_Land_FHV/FeatureServer/0) | New Zealand's national, conservation and forest parks: outlines, names, recorded areas | CC BY 4.0, "Crown Copyright: Department of Conservation Te Papa Atawhai" |
| [DOC Tracks](https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services/DOC_Tracks_Open_Data/FeatureServer/0) | New Zealand's tracks and their track categories | CC BY 4.0, as above |
| [DOC huts, campsites and visitor centres](https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services) | Huts, campsites and their pages and bookings | CC BY 4.0, as above |
| [DOC national park pages](https://www.doc.govt.nz/parks-and-recreation/places-to-go/national-parks/) | Each park's official page and the PDFs it links | Crown copyright; linked, nothing extracted |
| [Stats NZ regional councils](https://services.arcgis.com/XTtANUDT8Va4DLwI/arcgis/rest/services/nz_regional_councils/FeatureServer/0), hosted by Eagle Technology | Which regions a place lies in | CC BY 4.0, "Contains data sourced from Stats NZ licensed for reuse under CC BY 4.0" |
| [GeoNet](https://www.geonet.org.nz/about/volcano/val) | Live volcanic alert levels, fetched by the app | CC BY 3.0 NZ, © Earth Sciences New Zealand |
| [Canadian Protected and Conserved Areas Database](https://maps-cartes.ec.gc.ca/arcgis/rest/services/CWS_SCF/CPCAD/MapServer/0) (Environment and Climate Change Canada) | Canada's national parks, marine conservation areas and provincial and territorial parks: outlines, names, official areas | Open Government Licence – Canada, "Contains information licensed under the Open Government Licence – Canada (Environment and Climate Change Canada, Canadian Protected and Conserved Areas Database)" |
| [Parks Canada open data](https://open.canada.ca/data/en/dataset/64a90e8d-5bc0-4027-8645-b5881b4068d4) — trails, facilities, accommodation, attendance | Trails and their difficulty ratings; campgrounds, huts and visitor centres; attendance for fiscal 2025–26 | Open Government Licence – Canada, "Contains information licensed under the Open Government Licence – Canada (Parks Canada)" |
| [Parks Canada park pages](https://parks.canada.ca/pn-np) | Each park's official page and the PDFs it links | Crown copyright; linked, nothing extracted |
| [MSC GeoMet weather alerts](https://api.weather.gc.ca/collections/weather-alerts) (Environment and Climate Change Canada) | Live weather alerts, fetched by the app | Open Government Licence – Canada |
| [Avalanche Canada](https://avalanche.ca) | Live avalanche forecasts for the mountain parks, fetched by the app | Credited to Avalanche Canada (some forecasts are Parks Canada's); relayed as published |
| [CAPAD 2024](https://fed.dcceew.gov.au/datasets/erin::collaborative-australian-protected-areas-database-capad-2024-terrestrial) (DCCEEW) | Australia's national parks: outlines, names, areas, managing agencies | CC BY 4.0, "© Commonwealth of Australia (Department of Climate Change, Energy, the Environment and Water), Collaborative Australian Protected Areas Database (CAPAD) 2024, CC BY 4.0" |
| [ABS ASGS Edition 3 (2021) states and territories](https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/STE/MapServer/0) | Which state or territory a place lies in | CC BY 4.0, "Australian Bureau of Statistics, Australian Statistical Geography Standard (ASGS) Edition 3, CC BY 4.0" |
| [Queensland Parks and Wildlife Service walking tracks](https://www.data.qld.gov.au/dataset/queensland-parks-and-wildlife-service-access) | Queensland's tracks and their Australian walking track grades | CC BY 4.0, "© State of Queensland (Department of the Environment, Tourism, Science and Innovation), CC BY 4.0" |
| Parks Australia's and the state and territory park agencies' pages | Each park's official page and the PDFs it links | Crown copyright; linked, nothing extracted |
| NSW Rural Fire Service, Emergency Management Victoria, Queensland Fire, WA's DFES, TasALERT | Live fire incidents and warnings near parks, fetched by the app from each service's public feed | Credited to each service; relayed as published |
| [NSW National Parks and Wildlife Service alerts](https://www.nationalparks.nsw.gov.au/) | Live park closures, fire bans and safety alerts, fetched by the app | Credited to the NPWS; relayed as published |
| [Kartverket — Turrutebasen](https://kartkatalog.geonorge.no/metadata/turrutebasen/d1422d17-6d95-4ef1-96ab-8af31744dd63) | Norway's marked trails and their published grades | CC BY 4.0, «©Kartverket» |
| [Copernicus GLO-30](https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model) | Elevation abroad: trail profiles, each park's measured lowest and highest ground, relief on the Park maps abroad | © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA; all rights reserved. Licence Art. 6: the organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 |

The app's Attributions screen covers all of the above, and map attribution shows
wherever tiles are drawn. How each bundled figure was built, and its known limits, is
recorded in the [reference data README](Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md).
Licensing and naming constraints are tracked in [`SPECIFICATION.md`](SPECIFICATION.md) §15.
