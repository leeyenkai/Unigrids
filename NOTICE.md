# Notices

The MIT licence in [`LICENSE`](LICENSE) covers the Unigrids source code only. The data
bundled in the app, and the data it fetches, keeps its own terms.

## Not affiliated with the National Park Service

Unigrids is an independent project. It uses public-domain NPS material and public
government data, never the NPS arrowhead, and does not imply endorsement by the National
Park Service or any other agency.

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
- **Wikimedia Commons** photographs are linked, not bundled, and each is shown with its
  own credit and licence (public domain, CC0, CC BY or CC BY-SA).
- **Apple Weather** data, once used, requires Apple's attribution.

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

The app's Attributions screen covers all of the above, and map attribution shows
wherever tiles are drawn. How each bundled figure was built, and its known limits, is
recorded in the [reference data README](Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md).
Licensing and naming constraints are tracked in [`SPECIFICATION.md`](SPECIFICATION.md) §15.
