"""Points of interest for the four pilot parks.

(park slug, poi slug, kind, name, lat, lon, rank, summary, has_stamp)

Coordinates are approximate, to four decimal places, and were authored by hand.
The pipeline replaces them with NPS API "places" and "visitorcenters" records.
Ranks fix the order the guide's "Major sights" panel, the 3D view's numbered
pins and the fly-through all share.
"""

SIGHT = "sight"
VC = "visitorCentre"

POIS = [
    # ---------------------------------------------------------------- Zion
    ("zion", "angels-landing", SIGHT, "Angels Landing", 37.2690, -112.9470, 1,
     "A fin of Navajo sandstone reached by switchbacks and a chained ridge, "
     "1,500 feet above the canyon floor.", False),
    ("zion", "the-narrows", SIGHT, "The Narrows", 37.2860, -112.9480, 2,
     "The Virgin River's slot canyon, in places twenty feet wide between "
     "thousand-foot walls. Walked in the river itself.", False),
    ("zion", "observation-point", SIGHT, "Observation Point", 37.2720, -112.9390, 3,
     "The canyon's highest viewpoint, looking down on Angels Landing.", False),
    ("zion", "emerald-pools", SIGHT, "Emerald Pools", 37.2510, -112.9570, 4,
     "Three stepped pools fed by seeps and a hanging garden of ferns.", False),
    ("zion", "court-of-the-patriarchs", SIGHT, "Court of the Patriarchs",
     37.2430, -112.9780, 5,
     "Three sandstone peaks named for Abraham, Isaac and Jacob.", False),
    ("zion", "weeping-rock", SIGHT, "Weeping Rock", 37.2700, -112.9380, 6,
     "An alcove where water that fell as rain centuries ago seeps from the "
     "rock face.", False),
    ("zion", "canyon-overlook", SIGHT, "Canyon Overlook", 37.2130, -112.9400, 7,
     "A short walk off the Zion–Mount Carmel Highway to a ledge above "
     "Pine Creek.", False),
    ("zion", "kolob-canyons", SIGHT, "Kolob Canyons", 37.4530, -113.2070, 8,
     "The park's quiet north-west corner: red finger canyons cut into the "
     "Kolob Terrace.", False),
    ("zion", "zion-canyon-visitor-center", VC, "Zion Canyon Visitor Center",
     37.2000, -112.9870, 0,
     "The main visitor centre at the south entrance, and the shuttle's first stop.",
     True),
    ("zion", "kolob-canyons-visitor-center", VC, "Kolob Canyons Visitor Center",
     37.4530, -113.2230, 0,
     "A small centre off Interstate 15 serving the Kolob Canyons road.", True),

    # -------------------------------------------------------------- Acadia
    ("acadia", "cadillac-mountain", SIGHT, "Cadillac Mountain", 44.3526, -68.2251, 1,
     "The highest headland on the eastern seaboard, and among the first places "
     "in the United States to catch the sunrise.", False),
    ("acadia", "jordan-pond", SIGHT, "Jordan Pond", 44.3210, -68.2530, 2,
     "A glacial tarn below the twin summits of the Bubbles, circled by a "
     "level shore path.", False),
    ("acadia", "thunder-hole", SIGHT, "Thunder Hole", 44.3190, -68.1890, 3,
     "A narrow inlet where an incoming swell slams air out of a sea cave with "
     "a boom.", False),
    ("acadia", "sand-beach", SIGHT, "Sand Beach", 44.3290, -68.1830, 4,
     "A pocket of shell sand between granite headlands, in water that rarely "
     "passes 55°F.", False),
    ("acadia", "otter-cliff", SIGHT, "Otter Cliff", 44.3100, -68.1900, 5,
     "A 110-foot granite wall dropping straight into the Atlantic.", False),
    ("acadia", "bass-harbor-head-light", SIGHT, "Bass Harbor Head Light",
     44.2220, -68.3370, 6,
     "An 1858 light station on the island's quiet south-western shore.", False),
    ("acadia", "schoodic-point", SIGHT, "Schoodic Point", 44.3350, -68.0600, 7,
     "The park's mainland section, where dark basalt dykes cut through pink "
     "granite ledges.", False),
    ("acadia", "park-loop-road", SIGHT, "Park Loop Road", 44.3380, -68.2080, 8,
     "Twenty-seven miles threading the eastern side of Mount Desert Island, "
     "designed to reveal the coast a view at a time.", False),
    ("acadia", "hulls-cove-visitor-center", VC, "Hulls Cove Visitor Center",
     44.4090, -68.2480, 0,
     "The main visitor centre, with the park film, ranger desk and trip planning.",
     True),
    ("acadia", "sieur-de-monts-nature-center", VC, "Sieur de Monts Nature Center",
     44.3600, -68.2080, 0,
     "A small nature centre beside the Wild Gardens of Acadia.", False),

    # --------------------------------------------------------- Yellowstone
    ("yellowstone", "old-faithful", SIGHT, "Old Faithful", 44.4605, -110.8281, 1,
     "The park's most predictable large geyser, erupting every 60 to 110 "
     "minutes to around 130 feet.", False),
    ("yellowstone", "grand-prismatic-spring", SIGHT, "Grand Prismatic Spring",
     44.5250, -110.8380, 2,
     "The largest hot spring in the United States, ringed in orange and green "
     "by heat-loving microbial mats.", False),
    ("yellowstone", "grand-canyon-of-the-yellowstone", SIGHT,
     "Grand Canyon of the Yellowstone", 44.7200, -110.4960, 3,
     "Twenty miles of canyon cut through hydrothermally altered rock, with two "
     "major waterfalls.", False),
    ("yellowstone", "mammoth-hot-springs", SIGHT, "Mammoth Hot Springs",
     44.9700, -110.7030, 4,
     "Travertine terraces built and abandoned as spring vents shift, sometimes "
     "within a season.", False),
    ("yellowstone", "lamar-valley", SIGHT, "Lamar Valley", 44.8980, -110.2300, 5,
     "Open sage grassland where bison, elk and wolves are most reliably seen "
     "at dawn and dusk.", False),
    ("yellowstone", "hayden-valley", SIGHT, "Hayden Valley", 44.6600, -110.4700, 6,
     "A broad former lakebed along the Yellowstone River, grazed by bison herds.",
     False),
    ("yellowstone", "norris-geyser-basin", SIGHT, "Norris Geyser Basin",
     44.7260, -110.7030, 7,
     "The park's hottest and most changeable basin, and home to Steamboat Geyser.",
     False),
    ("yellowstone", "yellowstone-lake", SIGHT, "Yellowstone Lake",
     44.4500, -110.3700, 8,
     "The largest high-elevation lake in North America, sitting partly inside "
     "the caldera.", False),
    ("yellowstone", "tower-fall", SIGHT, "Tower Fall", 44.8930, -110.3880, 9,
     "A 132-foot fall dropping between volcanic pinnacles into the Yellowstone "
     "River.", False),
    ("yellowstone", "old-faithful-visitor-education-center", VC,
     "Old Faithful Visitor Education Center", 44.4590, -110.8290, 0,
     "Geyser predictions, hydrothermal exhibits and a ranger desk.", True),
    ("yellowstone", "canyon-visitor-education-center", VC,
     "Canyon Visitor Education Center", 44.7340, -110.4950, 0,
     "Exhibits on the Yellowstone volcano and the caldera beneath the park.", True),
    ("yellowstone", "albright-visitor-center", VC, "Albright Visitor Center",
     44.9760, -110.6990, 0,
     "At Mammoth, in the old Fort Yellowstone bachelor officers' quarters.", True),
    ("yellowstone", "grant-village-visitor-center", VC,
     "Grant Village Visitor Center", 44.3930, -110.5580, 0,
     "Exhibits on fire's part in the park's ecology.", True),

    # ------------------------------------------- Great Smoky Mountains
    ("great-smoky-mountains", "kuwohi", SIGHT, "Kuwohi (Clingmans Dome)",
     35.5628, -83.4986, 1,
     "The highest point in the park and on the Appalachian Trail, restored in "
     "2024 to its Cherokee name.", False),
    ("great-smoky-mountains", "cades-cove", SIGHT, "Cades Cove",
     35.6030, -83.8370, 2,
     "A broad valley of preserved homesteads, churches and a working grist mill, "
     "circled by an eleven-mile loop road.", False),
    ("great-smoky-mountains", "newfound-gap", SIGHT, "Newfound Gap",
     35.6110, -83.4250, 3,
     "The lowest drivable pass through the range, on the state line at "
     "5,046 feet.", False),
    ("great-smoky-mountains", "laurel-falls", SIGHT, "Laurel Falls",
     35.6800, -83.5930, 4,
     "An eighty-foot two-tier fall at the end of a paved, much-walked trail.",
     False),
    ("great-smoky-mountains", "alum-cave-trail", SIGHT, "Alum Cave Trail",
     35.6290, -83.4510, 5,
     "Past Arch Rock and the Alum Cave Bluffs to the summit of Mount LeConte.",
     False),
    ("great-smoky-mountains", "roaring-fork", SIGHT,
     "Roaring Fork Motor Nature Trail", 35.6880, -83.4780, 6,
     "A one-way loop through old-growth forest, past log cabins and a tumbling "
     "mountain stream.", False),
    ("great-smoky-mountains", "cataloochee", SIGHT, "Cataloochee",
     35.6350, -83.1060, 7,
     "A remote eastern valley with standing frame buildings and a reintroduced "
     "elk herd.", False),
    ("great-smoky-mountains", "deep-creek", SIGHT, "Deep Creek",
     35.4640, -83.4340, 8,
     "Three waterfalls within easy reach of one trailhead on the park's southern "
     "edge.", False),
    ("great-smoky-mountains", "sugarlands-visitor-center", VC,
     "Sugarlands Visitor Center", 35.6860, -83.5370, 0,
     "The main Tennessee-side centre, two miles from Gatlinburg.", True),
    ("great-smoky-mountains", "oconaluftee-visitor-center", VC,
     "Oconaluftee Visitor Center", 35.5150, -83.3060, 0,
     "The North Carolina entrance, beside the Mountain Farm Museum.", True),
    ("great-smoky-mountains", "cades-cove-visitor-center", VC,
     "Cades Cove Visitor Center", 35.5920, -83.8320, 0,
     "Midway around the Cades Cove loop, at the Cable Mill historic area.", True),
]
