import Foundation

extension LandForm {
    struct Landmark {
        /// What shape it is, which matters more than its size.
        ///
        /// The first version of this drew everything with a cosine falloff — flat at
        /// the summit, steep at the foot. That is a dome, and it is right for Half Dome
        /// and Cadillac and wrong for everything else: a tall narrow one is not a
        /// mountain at all.
        enum Profile {
            /// Rounded on top, steepening towards the foot. Glaciated granite.
            case dome
            /// Straight flanks to a sharp summit. A horn.
            case peak
            /// Concave flanks flaring out to a broad base, cut off flat at the top
            /// with a shallow crater in it. The stratovolcano profile — St Helens,
            /// Rainier — and the reason those read as mountains from fifty miles away.
            case volcano
            /// A lone stratovolcano at rest, with nothing round it: Fuji. Concave flanks
            /// close to a square law from summit to foot — steep under the rim,
            /// flattening into a foot many times wider than the mountain is tall, which
            /// is near enough how Fuji's own slopes fall — and a small flat summit for
            /// the crater. More concave than `.volcano`, which is drawn to stand over a
            /// forest at a distance; standing alone over a lake, the curve of the
            /// flanks is the whole silhouette and has to be the right one.
            case cone
        }

        let x: Double
        let z: Double
        let width: Double
        let depth: Double
        let height: Double
        let profile: Profile
        /// One side cut away to a sheer face, the way ice cut Half Dome. Nil for none.
        let shear: Shear?
        /// How many ridges run down from the summit. A whole number, so the pattern
        /// closes on itself instead of leaving a seam along one bearing.
        let spurs: Int
        /// How deeply those ridges, and the rock's own grain between them, are cut
        /// into the flanks — as a fraction of height.
        ///
        /// Zero leaves the profile analytic, which is what ice-scoured granite wants.
        /// Anything meant to read as a *mountain* needs some: `rise` is a curve of one
        /// variable, so on its own it sweeps a surface of revolution — the same
        /// silhouette from every bearing, smooth to the pixel. Dropped onto ground
        /// made of noise, that is not a peak, it is a traffic cone.
        let rock: Double
        /// What it stands on: a lift over its whole footprint, so it rises out of the
        /// ground around it rather than merging into it. Zero for an island, which
        /// should meet the water on a sloping shore — on a plinth it was a drum with a
        /// dome on top, a cake on a plate, with a sheer skirt all the way round.
        let plinth: Double

        init(
            x: Double,
            z: Double,
            width: Double,
            depth: Double,
            height: Double,
            profile: Profile,
            shear: Shear? = nil,
            spurs: Int = 6,
            rock: Double = 0,
            plinth: Double = 0.10
        ) {
            self.x = x
            self.z = z
            self.width = width
            self.depth = depth
            self.height = height
            self.profile = profile
            self.shear = shear
            self.spurs = spurs
            self.rock = rock
            self.plinth = plinth
        }

        /// The radius of the volcano's truncated summit, as a fraction of its foot.
        private static let crater = 0.08
        /// The same for a cone, whose crater is small against so broad a foot.
        private static let summit = 0.05

        /// A sheer face cut through a landmark along a plane.
        ///
        /// The face can look any way, and which way matters more than anything else
        /// about it. Cut square to the x axis, as it first was, Half Dome's face ran
        /// straight away from the camera and was seen exactly edge-on: there was no
        /// face to see, and no cut in the silhouette either. Turned towards the camera
        /// and to one side, the face shows as a wall and its edge as the vertical drop
        /// in the skyline that is the whole of what makes Half Dome recognisable.
        struct Shear {
            /// The way the face looks, in radians in the ground plane: zero is screen
            /// right, a quarter turn is straight away from the camera.
            let facing: Double
            /// How far from the summit the face is cut, as a fraction of the radius.
            /// Negative cuts behind the summit, so the high point stands at the brink.
            let at: Double
        }

        /// Height at a normalised distance from the summit, 0 at the centre to 1 at
        /// the foot.
        func rise(at distance: Double) -> Double {
            let r = min(max(distance, 0), 1)
            return switch profile {
            case .dome: cos(r * .pi / 2) * height
            case .peak: (1 - r) * height
            case .volcano:
                // Truncated, not pointed and not rounded. A point is a drawing of a
                // volcano; a rounded top on steep flanks is a shape nobody wants on
                // their home screen. A flat rim with a dip inside it is the one
                // silhouette that only a volcano has.
                r < Self.crater
                    ? (pow(1 - Self.crater, 1.7) - 0.035 * (1 - r / Self.crater)) * height
                    : pow(1 - r, 1.7) * height
            case .cone:
                r < Self.summit
                    ? (pow(1 - Self.summit, 2.1) - 0.02 * (1 - r / Self.summit)) * height
                    : pow(1 - r, 2.1) * height
            }
        }
    }
}
