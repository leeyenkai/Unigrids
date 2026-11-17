import UnigridsCore

/// The national parks that knowingly lack a figure the bundled tests otherwise require,
/// each for a stated reason. An absent figure is correct; a plausible wrong one ships to
/// the reader as fact (AGENTS.md).
enum KnownGaps {
    /// Their sources disagree on the area, so none is shown: Mingan (Parks Canada
    /// "approximately 100 km²", CPCAD 150.7), Bruce Peninsula (enlarged by purchase since
    /// its scheduled area), Thousand Islands (no Parks Canada figure), Kakadu (Parks
    /// Australia "almost 20,000 km²" against CAPAD's mapped area), Naracoorte (CAPAD's
    /// gazetted 5,941 ha against 660) and Nitmiluk (CAPAD and the NT disagree).
    static let area: Set<UnigridsID> = [
        "ca-np-mingan-archipelago", "ca-np-bruce-peninsula", "ca-np-thousand-islands",
        "au-np-kakadu", "au-np-naracoorte-caves", "au-np-nitmiluk",
    ]

    /// No agency states a founding year, or the sources give two; CAPAD's gazettal
    /// dates are not founding years, so none stands in.
    static let year: Set<UnigridsID> = [
        "au-np-budj-bim", "au-np-franklin-gordon-wild-rivers", "au-np-great-sandy",
        "au-np-litchfield", "au-np-nitmiluk", "au-np-whitsunday-islands", "au-np-wollumbin",
    ]

    /// Fewer than three sights the agency names and places: Pulu Keeling has no public
    /// access, Murujuga's guide keeps to its two public sites, and Mole Creek Karst's to
    /// its two show caves.
    static let sights: Set<UnigridsID> = [
        "au-np-pulu-keeling", "au-np-murujuga", "au-np-mole-creek-karst",
    ]
}
