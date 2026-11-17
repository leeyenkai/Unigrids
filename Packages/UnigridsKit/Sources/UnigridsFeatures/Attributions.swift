import Foundation

// The sources Unigrids credits, as Settings › About lists them (SPECIFICATION.md §15,
// NOTICE.md).

/// The attributions the bundled and fetched data require, in one list so the screen and
/// the repository's own README cannot drift apart.
struct Attribution: Identifiable {
    let name: String
    let terms: String

    var id: String {
        name
    }

    static let all: [Attribution] = [
        Attribution(
            name: "National Park Service",
            terms: "Park descriptions, fees, hours, visitor centres, alerts and photographs from "
                + "the NPS Data API; outlines from the NPS Land Resources Division. Public-domain "
                + "US government works, used without the NPS arrowhead and without implying "
                + "endorsement."
        ),
        Attribution(
            name: "USGS PAD-US",
            terms: "Every state park, and monument and refuge outlines and areas, from the "
                + "Protected Areas Database of the United States, a public-domain USGS data "
                + "release; state park managers as PAD-US names them."
        ),
        Attribution(
            name: "NPS Visitor Use Statistics",
            terms: "Monthly and annual recreation visits to National Park Service sites, from "
                + "the NPS's published visitor use data, dedicated to the public domain (CC0)."
        ),
        Attribution(
            name: "Wikipedia",
            terms: "Overviews of places with no agency prose, adapted from the opening of each "
                + "place's Wikipedia article — used only where the article's title and location "
                + "match the place — under CC BY-SA 4.0, credited and linked on each page."
        ),
        Attribution(
            name: "Other federal lands",
            terms: "National forest and grassland boundaries from the US Forest Service; "
                + "wildlife refuge boundaries from the US Fish and Wildlife Service; National "
                + "Conservation Lands from the Bureau of Land Management; National Natural "
                + "Landmarks from the National Park Service; scenic byways from the Federal "
                + "Highway Administration; state outlines from the US Census Bureau. All "
                + "public-domain US government works."
        ),
        Attribution(
            name: "National Transportation Atlas Database",
            terms: "Interstates, US highways and the Amtrak network and stations, from the US "
                + "Department of Transportation's Bureau of Transportation Statistics. A US "
                + "government work, unrestricted public use."
        ),
        Attribution(
            name: "Trails and elevation",
            terms: "Trail lines from the NPS Public Trails dataset, and for Sequoia and Kings "
                + "Canyon from OpenStreetMap; elevation, and the highest and lowest ground of "
                + "parks the NPS gives no figure for, from the USGS 3D Elevation Program "
                + "(3DEP), public domain. Measured by Unigrids."
        ),
        Attribution(
            name: "Official brochures",
            terms: "Brochures and maps are National Park Service publications, fetched from "
                + "nps.gov and shown as published, with their credits."
        ),
        Attribution(
            name: "Ministry of the Environment, Japan",
            terms: "Japan's national park areas and zones (the ministry's nps.zip), its lists "
                + "of national and quasi-national parks, and its annual visitor counts, under "
                + "the Public Data License 1.0; edited by Unigrids. Guides to Japan's parks are "
                + "written for Unigrids from the ministry's pages and others, named in each."
        ),
        Attribution(
            name: "Norwegian Environment Agency",
            terms: "Norway's national parks, protected landscapes and nature reserves — "
                + "boundaries, official names in every language, dates and managers — from "
                + "Naturvernområder. Kilde: Miljødirektoratet. Norwegian Licence for Open "
                + "Government Data (NLOD 2.0)."
        ),
        Attribution(
            name: "Kartverket and Natural Earth",
            terms: "Norway's county boundaries and its marked trails with their published "
                + "grades (Turrutebasen), ©Kartverket, CC BY 4.0; Japan's prefecture "
                + "boundaries from Natural Earth, public domain."
        ),
        Attribution(
            name: "Department of Conservation, New Zealand",
            terms: "New Zealand's national, conservation and forest parks, its tracks with "
                + "their categories, huts, campsites and visitor centres, from DOC's open data "
                + "under CC BY 4.0; edited by Unigrids. Guides are written for Unigrids from "
                + "DOC's pages and others, named in each."
        ),
        Attribution(
            name: "Parks Canada and CPCAD",
            terms: "Canada's national parks, marine conservation areas and provincial parks "
                + "from the Canadian Protected and Conserved Areas Database; Parks Canada's "
                + "trails with their difficulty ratings, its facilities and accommodation, "
                + "and its attendance figures. Open Government Licence – Canada. Guides are "
                + "written for Unigrids from Parks Canada's pages and others, named in each."
        ),
        Attribution(
            name: "Environment Canada and Avalanche Canada",
            terms: "Weather alerts from Environment and Climate Change Canada's MSC GeoMet, "
                + "Open Government Licence – Canada; avalanche forecasts from Avalanche "
                + "Canada, some written by Parks Canada."
        ),
        Attribution(
            name: "GeoNet and Stats NZ",
            terms: "Volcanic alert levels from GeoNet, © Earth Sciences New Zealand, CC BY "
                + "3.0 NZ; regional council boundaries from Stats NZ, hosted by Eagle "
                + "Technology, CC BY 4.0."
        ),
        Attribution(
            name: "Copernicus GLO-30",
            terms: "Elevation outside the US — trail profiles, each park's measured "
                + "lowest and highest ground, relief on their offline park maps. © DLR e.V. "
                + "2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under "
                + "COPERNICUS by the European Union and ESA; all rights reserved. The "
                + "organisations in charge of the Copernicus programme by law or by "
                + "delegation do not incur any liability for any use of the Copernicus "
                + "WorldDEM-30. Measured by Unigrids."
        ),
        Attribution(
            name: "Wikidata",
            terms: "The links between places abroad and their Wikipedia articles and "
                + "photographs, CC0."
        ),
        Attribution(
            name: "Wikimedia Commons",
            terms: "Photographs of state parks, monuments and refuges, and of the parks "
                + "abroad, each credited to its photographer under the licence shown "
                + "with it."
        ),
        Attribution(
            name: "OpenStreetMap",
            terms: "Trail lines in Sequoia and Kings Canyon, in Japan, and in Norway's parks "
                + "Turrutebasen does not cover; outlines of Japan's quasi-national "
                + "parks; huts, railway stations and lines abroad; and the roads "
                + "and water drawn in the offline park maps: © OpenStreetMap contributors, "
                + "available under the Open Database Licence (ODbL)."
        ),
        Attribution(
            name: "Apple Maps",
            terms: "Base maps, satellite imagery and 3D terrain."
        ),
        Attribution(
            name: "Open-Meteo",
            terms: "Historical weather from the ERA5 reanalysis, under CC BY 4.0."
        ),
    ]
}
