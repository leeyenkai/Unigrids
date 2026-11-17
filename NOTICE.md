# Notices

The MIT licence in [`LICENSE`](LICENSE) covers the Unigrids source code only. The data
bundled in the app, and the data it fetches, keeps its own terms.

## Not affiliated with any park authority

Unigrids is an independent project. It uses public-domain NPS material and public
government data, never the NPS arrowhead, and does not imply endorsement by the National
Park Service or any other agency. The same holds abroad: it is not affiliated with
Japan's Ministry of the Environment or the Norwegian Environment Agency, and never uses
Japan's national park mark (国立公園統一マーク), the ministry's logo or the Norges
nasjonalparker brand.

## Third-party terms

- **National Park Service** text, maps, brochures and photographs are public-domain US
  government works. Some photographs and artwork inside NPS publications carry
  third-party rights; those are shown only as published, with their credits, and never
  extracted. The 234 photographs bundled under
  `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/images/` are NPS
  images whose credit names the NPS.
- **OpenStreetMap** data is © OpenStreetMap contributors, available under the
  [Open Database Licence](https://www.openstreetmap.org/copyright) (ODbL).
- **Open-Meteo** data is available under CC BY 4.0 and is free for non-commercial use.
- **Recreation Information Database** (RIDB) data is available under CC BY.
- **Wikimedia Commons** photographs are linked, not bundled, for US places outside the
  NPS; for Japan's and Norway's national parks they are bundled, resized, as the guides'
  photographs. Each is shown with its own credit and licence.
- **Apple Weather** data, once used, requires Apple's attribution.
- **Japan's Ministry of the Environment** content is used under the Public Data License
  1.0, with the source named and edits marked as Unigrids'. Photographs the ministry marks
  as another provider's are not reused.
- **Norwegian government data** (Miljødirektoratet, Kartverket, NVE) is used under the
  Norwegian Licence for Open Government Data (NLOD 2.0) or CC BY 4.0, with each source
  named.
- This is a private hobby app: the owner has chosen to name every source used rather
  than leave one out for its licence. Guide prose for Japan and Norway is written for
  Unigrids and never copied; the sources each guide drew on are listed in it.

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
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | Japan's quasi-national park outlines; huts, railway stations and lines in Japan and Norway; Japan's trails, and Norway's where Turrutebasen has none; roads and water for the Chubu-Sangaku and Jotunheimen Park maps | ODbL: attribution and share-alike |
| [Kartverket — Turrutebasen](https://kartkatalog.geonorge.no/metadata/turrutebasen/d1422d17-6d95-4ef1-96ab-8af31744dd63) | Norway's marked trails and their published grades | CC BY 4.0, «©Kartverket» |
| [Copernicus GLO-30](https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model) | Elevation abroad: trail profiles, each park's measured lowest and highest ground, relief on the two Park maps abroad | © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA; all rights reserved. Licence Art. 6: the organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 |

The app's Attributions screen covers all of the above, and map attribution shows
wherever tiles are drawn. How each bundled figure was built, and its known limits, is
recorded in the [reference data README](Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md).
Licensing and naming constraints are tracked in [`SPECIFICATION.md`](SPECIFICATION.md) §15.
