import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog

/// Puts a place on the reader's wishlist, or takes it off (SPECIFICATION.md §9).
struct WishToggle: View {
    @Environment(\.modelContext) private var context
    @Query private var wishes: [Wish]
    let placeID: UnigridsID

    init(placeID: UnigridsID) {
        self.placeID = placeID
        let raw = placeID.rawValue
        _wishes = Query(filter: #Predicate<Wish> { $0.placeID == raw })
    }

    var body: some View {
        let isWished = !wishes.isEmpty
        let name = isWished ? "On your wishlist" : "Add to wishlist"
        Button {
            _ = try? LogStore(context: context).toggleWish(placeID)
        } label: {
            Label(name, symbol: isWished ? .wished : .wish)
        }
        .help(name)
        .accessibilityValue(isWished ? "On" : "Off")
        .sensoryFeedback(.selection, trigger: isWished)
    }
}
