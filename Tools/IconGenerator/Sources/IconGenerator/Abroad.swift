import Foundation

// The land of the parks abroad, kept apart from the US ten's table in `Heightfield.swift`.
// Their colours are in `AbroadColours.swift`.

extension LandForm {
    // Fuji over the lakes at its northern foot, as from their shore: a sheet of
    // water across the front of the frame, low forested hills along the far
    // side of it, and the cone standing alone over them, white on its upper
    // half and dark below.
    //
    // The camera stands at the water's edge, low. Any higher and the lake falls
    // behind the brochures, and the lake — with the dark flanks under the cap —
    // is what says *which* volcano this is: Olympic already has a cone, snowed
    // on to its foot, over forest.
    //
    // The far shore comes out nearly level, and that is right rather than a
    // shortcut: from a camera this close to the water, a shoreline wandering a
    // long way in and out moves only a few rows up and down the frame.
    static let fuji = LandForm(
        relief: 0.26, featureScale: 0.75, octaves: 3, crest: .rounded, shaping: 1.40,
        beds: 0, bedding: 0, canyon: 0, foreground: 1.60, lake: 0.04,
        seaLevel: 0.05, river: 0,
        // In units of the hills' relief, so well above them: the cap belongs to
        // the upper part of the cone and nothing else reaches it.
        snowLine: 1.58, snowTop: 2.00,
        flora: .conifer, floraDensity: 0.75, cameraHeight: 0.16,
        landmarks: [
            // One cone, symmetrical, its foot far wider than it is tall and its
            // summit cut off flat by the crater. Fluted shallowly, for the
            // gullies the snow runs down in stripes. Shallower from front to
            // back than across, so its foot ends behind the far shore instead of
            // rising straight out of the lake.
            .init(
                x: 0.00,
                z: 2.60,
                width: 2.50,
                depth: 1.40,
                height: 0.80,
                profile: .cone,
                spurs: 18,
                rock: 0.14,
                plinth: 0
            ),
        ]
    )

    /// A long lake in a glacial trough, as Gjende lies: green water running away
    /// from the shore the camera stands on, steep dark walls either side, peaks
    /// and ridges over them with snow lying wherever the ground is gentle enough
    /// to keep it, and mountain birch along the foot of the slopes. The land is
    /// noise, like every park's — no particular ridge is drawn — but every part
    /// of the view is one the place has.
    ///
    /// Peaked like Rocky Mountain's range, but cut by a trough rather than
    /// standing across an open valley: this is the view along the lake, and the
    /// lake is what makes it Jotunheimen rather than another range. Low ground in
    /// front as well, so the walls start out past the brochures; without it, the
    /// nearest wall rose straight up the whole left third of the frame.
    static let jotunheimen = LandForm(
        relief: 1.20, featureScale: 1.15, octaves: 4, crest: .peaks, shaping: 1.90,
        beds: 0, bedding: 0, canyon: 0.50, canyonWalls: 3.0, foreground: 1.50,
        lake: 0.20, seaLevel: 0.05, river: 0, snowLine: 0.30, snowTop: 0.46,
        snowSlope: 0.50,
        flora: .birchwood, floraDensity: 0.80, cameraHeight: 0.30,
        landmarks: [
            // A horn at the head of the lake. The trough runs on past the end
            // of the march, and without something standing across it the
            // valley ended in open sky. Fluted deep and cut away on one side, so
            // it is a summit ice has worked on all round, not a cone.
            .init(
                x: 0.10, z: 3.05, width: 1.05, depth: 0.80, height: 0.95,
                profile: .peak, shear: .init(facing: 0.35, at: 0.18),
                spurs: 7, rock: 0.55, plinth: 0
            ),
        ]
    )

    /// Aoraki over Hooker Lake, from its shore at the end of the Hooker Valley track: a
    /// grey glacial lake with ice afloat on it, tussock-brown moraine either side, and
    /// the mountain white over all of it at the head of the valley.
    ///
    /// The ice is what makes it this lake and no other: Fuji and Jotunheimen already
    /// have a mountain over water, and neither has bergs calved from a glacier drifting
    /// down it. The mountain is a massif, not noise or a landmark, because its long
    /// summit ridge is its outline — the summit a little right of centre, the ridge
    /// stepping down to the left over Middle and Low Peak, and a steeper fall to the
    /// right.
    static let aoraki = LandForm(
        relief: 0.55, featureScale: 1.0, octaves: 4, crest: .peaks, shaping: 1.9,
        beds: 0, bedding: 0, canyon: 0.30, canyonWalls: 2.6, foreground: 1.5, lake: 0.04,
        seaLevel: 0.05, river: 0, snowLine: 0.91, snowTop: 1.05, snowSlope: 0.50,
        // The snow lies on the mountain and nowhere lower: started any lower, it put a
        // grey half-coat on the moraine in front, which read as mist over the valley.
        flora: .icebergs, floraDensity: 0.8, cameraHeight: 0.18, landmarks: [],
        massifs: [
            // Aoraki itself, ribbed with rock where the face is too steep to hold snow.
            .init(
                crest: [
                    .init(x: -1.83, z: 2.5, height: 0.20), .init(x: -1.25, z: 2.46, height: 0.49),
                    .init(x: -0.83, z: 2.46, height: 0.63), .init(x: -0.62, z: 2.47, height: 0.60),
                    .init(x: -0.50, z: 2.48, height: 0.62), .init(x: -0.375, z: 2.5, height: 0.71),
                    .init(x: -0.167, z: 2.5, height: 0.75), .init(x: 0.05, z: 2.52, height: 0.80),
                    .init(x: 0.15, z: 2.54, height: 0.88), .init(x: 0.24, z: 2.52, height: 0.80),
                    .init(x: 0.42, z: 2.5, height: 0.68), .init(x: 0.71, z: 2.46, height: 0.55),
                    .init(x: 1.17, z: 2.42, height: 0.38), .init(x: 1.83, z: 2.42, height: 0.20),
                ],
                depth: 0.9, flank: 1.5, gullies: 0.25, gullyScale: 7, jag: 0.03,
                spurs: 0.6
            ),
            // The moraine and the glacier's lower valley in front of it: low, grey and
            // broken, and as high as the mountain's snow line, so the snow starts behind
            // a skyline of its own rather than at a level line drawn across the face.
            .init(
                crest: [
                    .init(x: -1.6, z: 2.0, height: 0.30), .init(x: -1.1, z: 2.0, height: 0.42),
                    .init(x: -0.75, z: 2.0, height: 0.37), .init(x: -0.4, z: 2.05, height: 0.45),
                    .init(x: -0.05, z: 2.05, height: 0.38), .init(x: 0.3, z: 2.05, height: 0.42),
                    .init(x: 0.7, z: 2.0, height: 0.48), .init(x: 1.1, z: 1.95, height: 0.40),
                    .init(x: 1.7, z: 1.95, height: 0.28),
                ],
                depth: 0.6, flank: 1.2, gullies: 0.2, gullyScale: 4, jag: 0.05,
                spurs: 0.6
            ),
        ]
    )

    /// Moraine Lake under the Valley of the Ten Peaks, from the Rockpile: water the
    /// turquoise only rock flour gives a lake, spruce and fir down to it on both sides,
    /// and the peaks standing in a row across the head of it.
    ///
    /// The row is the place. Each summit is set out by hand at its own height and
    /// spacing, from the broad one on the left to the tallest towards the right, because
    /// noise cannot be asked for ten peaks, and an even row of them is a saw blade.
    static let moraineLake = LandForm(
        relief: 0.50, featureScale: 1.1, octaves: 4, crest: .peaks, shaping: 1.9,
        beds: 0, bedding: 0, canyon: 0.85, canyonWalls: 3.0, foreground: 0.6,
        lake: 0.30, seaLevel: 0.05, river: 0, snowLine: 1.2, snowTop: 1.7, snowSlope: 0.28,
        // Little snow, and only on the ledges: it is a summer view. On the faces the
        // light alone leaves half a coat, which turned the whole wall pale grey.
        flora: .conifer, floraDensity: 0.8, cameraHeight: 0.32, landmarks: [],
        massifs: [
            .init(
                crest: [
                    .init(x: -2.0, z: 2.35, height: 0.35), .init(x: -1.62, z: 2.3, height: 0.80),
                    .init(x: -1.45, z: 2.3, height: 0.97), .init(x: -1.30, z: 2.3, height: 0.93),
                    .init(x: -1.12, z: 2.35, height: 0.74), .init(x: -0.98, z: 2.4, height: 0.86),
                    .init(x: -0.86, z: 2.4, height: 0.76), .init(x: -0.72, z: 2.4, height: 0.84),
                    .init(x: -0.55, z: 2.45, height: 0.70), .init(x: -0.42, z: 2.45, height: 0.82),
                    .init(x: -0.30, z: 2.45, height: 0.75), .init(x: -0.18, z: 2.45, height: 0.80),
                    .init(x: -0.02, z: 2.5, height: 0.68), .init(x: 0.16, z: 2.5, height: 0.96),
                    .init(x: 0.28, z: 2.5, height: 0.84), .init(x: 0.42, z: 2.5, height: 0.92),
                    .init(x: 0.56, z: 2.5, height: 0.74), .init(x: 0.76, z: 2.5, height: 1.02),
                    .init(x: 0.88, z: 2.5, height: 0.90), .init(x: 1.02, z: 2.5, height: 0.78),
                    .init(x: 1.20, z: 2.5, height: 0.94), .init(x: 1.36, z: 2.5, height: 0.80),
                    .init(x: 1.50, z: 2.5, height: 0.86), .init(x: 1.75, z: 2.5, height: 0.60),
                    .init(x: 2.1, z: 2.5, height: 0.40),
                ],
                depth: 0.75, flank: 1.3, gullies: 0.35, gullyScale: 9, jag: 0.04,
                spurs: 0.7
            ),
        ]
    )

    /// Cradle Mountain over Dove Lake, from its northern shore: dark water across the
    /// front of the frame, scrub and forest up from the far shore, and the mountain's
    /// crown of dolerite standing on its own talus — the Little Horn on its own to the
    /// left, then Weindorfers Tower, Smithies Peak and the summit along the crest.
    ///
    /// Dolerite sets in columns, and the columns are the crown: a sheer band along the
    /// top of the mountain, as tall as the summits are high, and striped straight down.
    static let cradleMountain = LandForm(
        relief: 0.55, featureScale: 0.9, octaves: 3, crest: .rounded, shaping: 3.2,
        beds: 0, bedding: 0, canyon: 0, foreground: 2.0, lake: 0.04,
        seaLevel: 0.05, river: 0, snowLine: 1.1, streaks: 0.7,
        flora: .none, floraDensity: 0, cameraHeight: 0.17, landmarks: [],
        massifs: [
            .init(
                crest: [
                    .init(x: -1.72, z: 2.35, height: 0.153), .init(
                        x: -1.204,
                        z: 2.27,
                        height: 0.316
                    ),
                    .init(x: -0.963, z: 2.23, height: 0.454), .init(
                        x: -0.877,
                        z: 2.21,
                        height: 0.557
                    ),
                    .init(x: -0.791, z: 2.2, height: 0.454), .init(
                        x: -0.671,
                        z: 2.17,
                        height: 0.385
                    ),
                    .init(x: -0.499, z: 2.15, height: 0.471), .init(
                        x: -0.396,
                        z: 2.15,
                        height: 0.626
                    ),
                    .init(x: -0.327, z: 2.15, height: 0.54), .init(
                        x: -0.189,
                        z: 2.15,
                        height: 0.591
                    ),
                    .init(x: -0.086, z: 2.15, height: 0.669), .init(x: 0.0, z: 2.15, height: 0.574),
                    .init(x: 0.103, z: 2.15, height: 0.643), .init(
                        x: 0.206,
                        z: 2.15,
                        height: 0.729
                    ),
                    .init(x: 0.31, z: 2.15, height: 0.66), .init(x: 0.413, z: 2.17, height: 0.677),
                    .init(x: 0.533, z: 2.2, height: 0.523), .init(x: 0.731, z: 2.25, height: 0.385),
                    .init(x: 1.118, z: 2.3, height: 0.265), .init(x: 1.892, z: 2.45, height: 0.11),
                ],
                depth: 1.0, flank: 2.2, cliff: 0.5, gullies: 0.16, gullyScale: 10, jag: 0.03,
                spurs: 0.5
            ),
        ]
    )
}
