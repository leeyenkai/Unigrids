import Foundation

/// The shape of the ground, as a handful of numbers per park.
///
/// Fifteen parks, and bespoke code for each would be fifteen places to get the same thing
/// subtly wrong. What actually differs between them is small and nameable: how much relief
/// there is, whether the crests are rounded, level or peaked, whether the rock steps in
/// beds, whether a river has cut through it, whether there is water, and whether a
/// landmark or a massif stands out of the rest. Everything else is the same noise.
///
/// So the parks are a table and this is the one function that reads it.
struct LandForm {
    /// Peak relief, in the same units as the camera's height.
    let relief: Double
    /// How large the landforms are. Lower is broader.
    let featureScale: Double
    /// More octaves is more detail. Two or three is right for an icon; a full fractal
    /// is detail nobody sees at 1024 and mud at 64.
    let octaves: Int
    /// What the high ground does at the top.
    let crest: Crest
    /// The power curve on the noise. Above 1 pushes ground down and makes the high
    /// places rarer; below 1 fills the frame with high ground.
    let shaping: Double
    /// How many beds the rock steps in, and how strongly. Zero for rock that does not
    /// bed. Kept light: treads wide enough to see alias along the line of sight, so the
    /// strata belong in the colour rather than the geometry.
    let beds: Double
    let bedding: Double
    /// How wide the low ground is. A small number is a slot canyon; a large one is a
    /// broad valley; zero is no low ground at all.
    ///
    /// Tall country needs low ground somewhere — this or `foreground`. Without it the
    /// camera has nowhere to stand and the terrain rises as one unbroken wall across
    /// the frame, which is what Olympic and Rocky Mountain both did at first.
    let canyon: Double
    /// How the canyon's walls rise: the exponent on its cross-section. Around 2 is a
    /// river's V; much higher is the U that ice leaves — a flat floor and walls that go
    /// straight up, which is Yosemite Valley and nothing else here.
    var canyonWalls = 2.1
    /// How far out from the camera the ground stays low before the relief rises to its
    /// full height. Zero for none.
    ///
    /// `canyon` cuts low ground running *away* from the camera, which frames every park
    /// that has it the same way: a wall each side and the view down the middle. That
    /// is right for Zion, and it is how Rocky Mountain came out looking like Zion in
    /// grey. Its own view is the other way round — an open valley floor, and the range
    /// standing across the back of it — so its low ground has to run *across* the
    /// frame, in front of the camera.
    let foreground: Double
    /// How far the land drops on the seaward side of the shoreline. Zero for no coast.
    ///
    /// A sea level on its own floods whatever is low, everywhere at once: the hollows
    /// between hills, never the open water. A coast is land on one side and ocean on
    /// the other, so the land is cut down on the far side of a shoreline that wanders
    /// in and out of headlands and coves — and whatever still stands above the water
    /// out there is an island.
    var coast = 0.0
    /// How far the low ground — the canyon's floor, or the foreground's — is sunk under
    /// the water, so it holds a lake from shore to shore. Zero for none.
    ///
    /// A sea level alone floods only the deepest hollows, and the noise puts those
    /// anywhere: a scatter of ponds, not a lake. Sinking the low ground itself gives one
    /// sheet of water with a shore that follows the land round it — down the length of
    /// a glacial trough for Gjende, across the front of the frame for the Fuji lakes.
    var lake = 0.0
    /// Everything at or under this is water, everywhere. Zero for a park with no sea.
    let seaLevel: Double
    /// A river along the floor of the low ground, as a fraction of the canyon's width.
    ///
    /// Distinct from `seaLevel`, which floods the whole frame at one height. A river is
    /// confined to the channel the canyon already cut, which is the only way to put the
    /// Colorado at the bottom of the Grand Canyon without drowning the rims.
    let river: Double
    /// Where snow starts to lie, as a fraction of relief. At or above `snowTop` means none.
    let snowLine: Double
    /// Where the snow lies unbroken, as a fraction of relief: the top of the ramp that
    /// starts at `snowLine`.
    ///
    /// One for a range, whose snow belongs to the range's own relief. A lone volcano
    /// standing twice the height of the hills round it needs its cap well above them,
    /// on the upper part of the cone only — capped at the hills' own height, the snow
    /// ran down to its foot and the mountain was white from top to bottom.
    var snowTop = 1.0
    /// The steepest ground that keeps its snow, on the renderer's scale of 0 for level
    /// and 1 for a wall — the slope, not the light, deciding where it lies. One leaves
    /// it to the light.
    ///
    /// The light sheds snow only from the faces turned to or from the sun, and leaves
    /// every other face half covered: a grey wash that reads as pale rock, not as snow.
    /// A glaciated range is the opposite — white in every cirque and on every ledge,
    /// and the dark rock showing on the walls between them.
    var snowSlope = 1.0
    /// How dark the streaks are that water leaves down steep rock. Zero for none.
    ///
    /// The black stripes down El Capitan and Half Dome's face are lichen and mineral
    /// left by water that runs the same lines every spring, and they are what make a
    /// granite wall read as a wall rather than as a smooth grey shape.
    var streaks = 0.0
    /// What grows here, and how thickly.
    let flora: Flora
    let floraDensity: Double
    /// Where the camera stands.
    ///
    /// A park whose relief rises past the camera swallows the frame — Olympic and Rocky
    /// Mountain both did, because neither has a canyon pulling the ground back down the
    /// way Zion's does. Tall country is looked at from higher up; flat country from
    /// lower down, or the horizon climbs out of the tile.
    let cameraHeight: Double
    /// Single forms standing above the rest: Half Dome, Cadillac, the volcano behind
    /// Olympic. Only for something that really is one shape on its own. A range is
    /// not a row of these — see `Crest.peaks` — and every attempt to build one out of
    /// them came out as a row of traffic cones.
    let landmarks: [Landmark]
    /// Mountain walls set out by their own skyline, for a mountain known by its outline
    /// (`Massif.swift`). Empty for every park whose mountains are noise.
    var massifs: [Massif] = []

    /// What stands on the ground, drawn as objects rather than as colour.
    ///
    /// Tinting the ground green says "something grows here"; it does not say what. A
    /// Joshua tree and a bald cypress are the subject of their parks, not a wash over
    /// them, so they are drawn.
    enum Crest {
        /// Rounded swells. Ice-scoured granite, a drowned coast, a floodplain.
        case rounded
        /// Sharp, but level: the sum of the octaves folded once, which puts a single
        /// crest line at exactly the maximum height. That is a rim, and it is right
        /// for canyon country, where the tops of the mesas really are flat.
        case rims
        /// Folded octave by octave. The crests of each scale fall in different
        /// places, so a summit is only as high as the number of them that happen to
        /// coincide there — and the range comes out with a hierarchy of summits at
        /// different heights instead of a table top with a fringe on it.
        case peaks
    }

    enum Flora {
        case none
        /// Stubby trunk, a few upswept arms. Mojave.
        case joshua
        /// Tall and narrow on a buttressed base, standing in water.
        case cypress
        /// Rounded clumps of hardwood on a tree island.
        case hammock
        /// Narrow spires.
        case conifer
        /// Giant sequoia standing among fir: the conifers, with every few trees a
        /// giant twice their height.
        case giantForest
        /// Mountain birch along the shore and up the lower slopes, and now and then a
        /// spruce or pine among it: the subalpine belt of a Norwegian valley, which
        /// is birch and not conifer.
        case birchwood
        /// No plants at all, but ice afloat on the lake — calved from the glacier at
        /// its head and drifting down it.
        case icebergs
    }
}

extension Scene {
    /// Ground height at a point, in the same units as the camera's own height. Water
    /// stands at sea level over anything lower.
    func height(x: Double, z: Double) -> Double {
        max(ground(x: x, z: z), landForm.seaLevel)
    }

    /// The ground itself, under the water as well as out of it — which is how the
    /// shading knows where the sea is shallow enough to break.
    func ground(x: Double, z: Double) -> Double {
        let form = landForm
        let u = x * form.featureScale
        let v = z * form.featureScale * 0.62
        let shaped = switch form.crest {
        case .rounded: Noise.fbm(x: u, y: v, octaves: form.octaves)
        case .rims: 1 - abs(Noise.fbm(x: u, y: v, octaves: form.octaves) * 2 - 1)
        case .peaks: Noise.peaks(x: u, y: v, octaves: form.octaves)
        }
        var height = pow(max(shaped, 0), form.shaping) * form.relief

        // The canyon: a meander cut down through everything, deepest at its middle.
        if form.canyon > 0 {
            let across = abs(x - riverCentre(z: z)) / form.canyon
            let cut = 1 - exp(-pow(across, form.canyonWalls))
            height *= 0.16 + 0.84 * cut
            if form.lake > 0 {
                height -= form.lake * (1 - cut)
            }
        }

        // The valley floor in front of the camera, rising into the range behind it.
        //
        // Flat for the first two-fifths of the way out, then rising. A ramp that starts
        // at the camera lifts the middle distance nearly as much as the far, and the
        // range comes forward to meet the camera instead of standing behind the floor.
        if form.foreground > 0 {
            let t = min(max((z / form.foreground - 0.4) / 0.6, 0), 1)
            height *= 0.12 + 0.88 * t * t * (3 - 2 * t)
            if form.lake > 0 {
                height -= form.lake * (1 - t * t * (3 - 2 * t))
            }
        }

        // The coast: the land drops away on the seaward side of the shore, steeply,
        // so the edge is a cliff and not a beach.
        //
        // The shore is broken by its own noise, at a scale much finer than the land's:
        // points, coves and rocks standing off the end of every ledge. A shoreline
        // that follows a smooth curve is a beach, and this coast has none.
        if form.coast > 0 {
            let broken = (Noise.fbm(x: x * 7.5, y: z * 7.5, octaves: 3) - 0.5) * 0.16
            let t = min(max((x - coastline(z: z) + 0.02 + broken) / 0.06, 0), 1)
            height -= form.coast * t * t * (3 - 2 * t)
        }

        // Bedding, lightly.
        if form.beds > 0 {
            let stepped = (height * form.beds).rounded(.down) / form.beds
            height = stepped * form.bedding + height * (1 - form.bedding)
        }

        for landmark in form.landmarks {
            let dx = (x - landmark.x) / landmark.width
            let dz = (z - landmark.z) / landmark.depth
            let toLandmark = sqrt(dx * dx + dz * dz)
            guard toLandmark < 1 else { continue }
            var swell = landmark.rise(at: toLandmark)

            // Ridges down the flanks, and the rock's grain in the gullies between
            // them. This is what the renderer needs to find a mountain here: it takes
            // its light from a finite difference across the surface, and a surface of
            // revolution has nothing in it to catch any.
            //
            // Faded in over the first quarter of the radius. The spur term turns on a
            // bearing, so its wavelength shrinks to nothing at the centre; left to run
            // all the way in, it is finer than the slope is measured and the summit
            // breaks up into noise instead of staying a summit.
            if landmark.rock > 0 {
                // Squared, so the crests come out narrow and the gullies between
                // them broad and concave. Left as a plain cosine it is a sine wave
                // wrapped round a cone, and a cone under a sine wave is a circus tent.
                let fluting = pow(cos(atan2(dz, dx) * Double(landmark.spurs)) * 0.5 + 0.5, 2)
                let grain = Noise.fbm(x: x * 3.4, y: z * 3.4, octaves: 3)
                let crest = fluting * 0.38 + grain * 0.62
                let reach = min(toLandmark / 0.25, 1)
                swell *= 1 - landmark.rock * reach * reach * (1 - crest)
            }

            // Sheared: everything beyond the face drops to a talus apron. Stepped over
            // a few hundredths rather than cut dead, so the slope the renderer lights
            // the face by is steep rather than infinite.
            if let shear = landmark.shear {
                let across = dx * cos(shear.facing) + dz * sin(shear.facing)
                let t = min(max((across - shear.at) / 0.05, 0), 1)
                swell *= 1 - 0.80 * t * t * (3 - 2 * t)
            }
            height = max(height, swell + landmark.plinth)
        }

        for massif in form.massifs {
            height = max(height, massif.height(x: x, z: z))
        }

        // Broken rock along a coast: ledges and boulders at a scale finer than the
        // land's own, on the mainland and the islands alike.
        if form.coast > 0 {
            height += (Noise.fbm(x: x * 16, y: z * 16, octaves: 2) - 0.5) * 0.045
        }

        return height + 0.015
    }

    var seaLevel: Double {
        landForm.seaLevel
    }

    /// Where the shore runs at this distance: land to the left of it, sea to the right.
    func coastline(z: Double) -> Double {
        -0.04 + sin(z * 2.1 + 0.8) * 0.13 + sin(z * 5.3 + 1.9) * 0.045
    }

    /// Where the river runs at this distance, in the same world units as `x`.
    func riverCentre(z: Double) -> Double {
        sin(z * 1.15) * 0.17 + sin(z * 2.7) * 0.05
    }

    var landForm: LandForm {
        switch self {
        case .zion:
            // Navajo Sandstone cut by the Virgin River: sheer walls along vertical
            // joints, bedded, with the canyon itself the subject.
            LandForm(
                relief: 0.62, featureScale: 0.78, octaves: 3, crest: .rims, shaping: 1.35,
                beds: 3, bedding: 0.12, canyon: 0.19, foreground: 0,
                seaLevel: 0, river: 0, snowLine: 1.1,
                flora: .none, floraDensity: 0, cameraHeight: 0.55, landmarks: []
            )
        case .grandCanyon:
            // The one park where the bedding *is* the landscape: rim to river through
            // cream Kaibab, pale Coconino, rust Hermit, red Supai and the Redwall. Wider
            // and deeper than Zion, and stepped rather than sheer.
            LandForm(
                relief: 0.92, featureScale: 0.46, octaves: 4, crest: .rims, shaping: 1.05,
                beds: 7, bedding: 0.18, canyon: 0.30, foreground: 0,
                seaLevel: 0, river: 0.14, snowLine: 1.1,
                flora: .none, floraDensity: 0, cameraHeight: 0.80, landmarks: []
            )
        case .yosemite:
            // The valley as it opens from Tunnel View: granite walls straight up out of
            // a flat, forested floor — El Capitan on the left, Cathedral Rocks on the
            // right — and Half Dome standing at the head of it.
            //
            // The walls are the valley's own cross-section, cut as a glacial U, not
            // landmarks. Drawn as cut domes, El Capitan and Cathedral Rocks came out as
            // two more copies of Half Dome's outline, and three of it is none of it.
            //
            // Half Dome's face looks almost straight across the line of sight. That is
            // what puts the cut in the skyline: cut the front off a dome and its back
            // half still spans the full width, so the outline stays a whole dome and
            // the face hides below it. The summit stands at the very brink, so the cut
            // is just to the left of it, and the dome is much broader than it is tall:
            // narrow and rounded, it was a gumdrop, and worse. It stands well clear of
            // the walls, as it does — four thousand feet over the floor to El
            // Capitan's three — or the near wall hides all but a sliver of it.
            LandForm(
                relief: 0.80, featureScale: 0.62, octaves: 3, crest: .rounded, shaping: 0.90,
                beds: 0, bedding: 0, canyon: 0.34, canyonWalls: 5, foreground: 0,
                seaLevel: 0, river: 0, snowLine: 1.1, streaks: 0.45,
                flora: .conifer, floraDensity: 0.7, cameraHeight: 0.50,
                landmarks: [
                    .init(
                        x: -0.07, z: 2.90, width: 1.45, depth: 1.10, height: 1.05,
                        profile: .dome, shear: .init(facing: 3.25, at: 0.03)
                    ),
                ]
            )
        case .sequoia:
            // The Giant Forest: an open floor among the trees, with the granite of the
            // Great Western Divide standing off behind them. The trees are the subject
            // and are placed by hand — see `Scene.specimens` — while the ground does
            // no more than give them somewhere to stand and something to stand against.
            LandForm(
                relief: 0.95, featureScale: 0.95, octaves: 4, crest: .peaks, shaping: 2.20,
                beds: 0, bedding: 0, canyon: 0, foreground: 2.10,
                seaLevel: 0, river: 0, snowLine: 0.50, streaks: 0.20,
                flora: .giantForest, floraDensity: 0.85, cameraHeight: 0.45, landmarks: []
            )
        case .rockyMountain:
            // An open valley floor of spruce and fir, and the range standing across the
            // back of it: granite summits at different heights, alpine tundra under
            // them, snow on whatever is flat enough to hold it. The view from the
            // valley, not from inside a gorge — that framing is Zion's.
            //
            // No landmark. A range is not a row of summits standing on a plain; it is
            // high ground to the horizon, with the summits as the places it happens to
            // rise highest, so the noise makes the mountains and nothing is drawn on
            // top of it. Cones were tried and failed twice over: a curve of one
            // variable has the same silhouette from every bearing and nothing for the
            // light to catch, and a summit only reads as a mountain at about thirty
            // degrees, which needs a foot wider than the frame. Anything narrow enough
            // to fit is a spike.
            //
            // The shaping is strong because folded noise sits mostly near its top: at
            // anything gentler the whole frame is high ground and the camera sees a
            // wall, not a range.
            LandForm(
                relief: 1.12, featureScale: 1.05, octaves: 4, crest: .peaks,
                shaping: 2.40, beds: 0, bedding: 0, canyon: 0, foreground: 1.85,
                seaLevel: 0, river: 0, snowLine: 0.30, flora: .conifer,
                floraDensity: 0.55, cameraHeight: 0.52, landmarks: []
            )
        case .olympic:
            // Rainforest to the crests of the ridges, and one snow-covered
            // stratovolcano standing over them.
            //
            // **Not the park's own geology.** Mount Olympus is not a volcano; it is a
            // glaciated peak of uplifted sea-floor rock, and the stratovolcanoes of the
            // Northwest are in the Cascades, across Puget Sound. The volcano is here
            // at the owner's direction, as the silhouette the region is known by. It
            // is an icon, not a claim — but recorded here so that nobody reads the
            // code as asserting otherwise.
            LandForm(
                relief: 0.52, featureScale: 0.92, octaves: 4, crest: .rims,
                shaping: 1.45, beds: 0, bedding: 0, canyon: 0.55, foreground: 0,
                seaLevel: 0.070, river: 0,
                // High enough that only the volcano holds snow. Snowed on, the ridges
                // in front of it bleach the whole left of the frame.
                snowLine: 0.90, flora: .conifer, floraDensity: 0.85, cameraHeight: 0.52,
                landmarks: [
                    // Twice as wide at the foot as it is tall, and set well back.
                    // Drawn any narrower it is a spike, and its proportions only work
                    // at a distance: a foot this wide would overfill the frame up
                    // close. The haze it picks up out there is how these mountains
                    // always look anyway.
                    .init(
                        x: 0.00,
                        z: 2.60,
                        width: 1.90,
                        depth: 2.20,
                        height: 1.05,
                        profile: .volcano,
                        spurs: 14,
                        rock: 0.20
                    ),
                ]
            )
        case .acadia:
            // The Park Loop shore: pink granite stepping down in ledges into the
            // Atlantic, spruce to the brink, surf on the rocks, islands standing off
            // the coast, and Cadillac's bare summit rising behind it all. The sea is the
            // other half of the park and gets half the frame.
            //
            // Stepped, so the rock comes out as ledges rather than swells: the granite
            // here is jointed into blocks, and it is the blocks the sea works on.
            LandForm(
                relief: 0.50, featureScale: 0.95, octaves: 4, crest: .rounded, shaping: 1.55,
                beds: 6, bedding: 0.40, canyon: 0, foreground: 0, coast: 0.22,
                seaLevel: 0.062, river: 0, snowLine: 1.1,
                flora: .conifer, floraDensity: 0.75, cameraHeight: 0.38,
                landmarks: [
                    // Cadillac Mountain: broad, far off, and bare at the top.
                    .init(
                        x: -0.95, z: 3.00, width: 1.15, depth: 1.00, height: 0.40,
                        profile: .dome
                    ),
                    // Islands standing off the coast, steep-sided and flat on top under
                    // their spruce, the way the Porcupines are.
                    .init(
                        x: 0.42, z: 1.70, width: 0.24, depth: 0.19, height: 0.21,
                        profile: .dome, plinth: 0
                    ),
                    .init(
                        x: 0.95, z: 2.45, width: 0.40, depth: 0.26, height: 0.23,
                        profile: .dome, plinth: 0
                    ),
                ]
            )
        case .joshuaTree:
            // Monzogranite weathered along its joints into piles of rounded boulders,
            // standing on a flat desert floor. Low relief, lumpy, nothing continuous.
            LandForm(
                relief: 0.30, featureScale: 1.70, octaves: 3, crest: .rounded, shaping: 1.30,
                beds: 0, bedding: 0, canyon: 0, foreground: 0,
                seaLevel: 0, river: 0, snowLine: 1.1,
                flora: .joshua, floraDensity: 0.9, cameraHeight: 0.46, landmarks: []
            )
        case .everglades:
            // Twenty feet of fall across the whole park. The sky and the sawgrass do all
            // the work, and the only relief is the tree islands standing out of it.
            LandForm(
                relief: 0.10, featureScale: 1.30, octaves: 2, crest: .rounded, shaping: 3.20,
                beds: 0, bedding: 0, canyon: 0, foreground: 0,
                seaLevel: 0.030, river: 0, snowLine: 1.1,
                flora: .hammock, floraDensity: 0.9, cameraHeight: 0.55, landmarks: []
            )
        case .congaree:
            // Flatter still: a floodplain with a twenty-foot drop over twenty-three
            // miles, under the tallest bottomland hardwood left in the country. The
            // water is the floor and the forest is the subject.
            LandForm(
                relief: 0.08, featureScale: 1.10, octaves: 2, crest: .rounded, shaping: 2.40,
                beds: 0, bedding: 0, canyon: 0, foreground: 0,
                seaLevel: 0.026, river: 0, snowLine: 1.1,
                flora: .cypress, floraDensity: 0.72, cameraHeight: 0.55, landmarks: []
            )
        case .fuji: .fuji
        case .jotunheimen: .jotunheimen
        case .aoraki: .aoraki
        case .moraineLake: .moraineLake
        case .cradleMountain: .cradleMountain
        }
    }
}
