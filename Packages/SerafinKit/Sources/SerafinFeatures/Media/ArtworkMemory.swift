import Foundation
import SwiftUI

/// What the app already knows about items' hero artwork, so a screen showing an item seen moments ago starts the way
/// it ended: the same backdrop, already loaded, and the tint taken from it.
///
/// Home's hero and the detail screen both show an item's backdrop full width. Opening an item from the hero, or
/// opening it again, finds its tint here at once rather than showing the play button and the toolbar in another
/// colour until the backdrop is measured again.
@MainActor enum ArtworkMemory {
    /// How many items are remembered; the oldest are forgotten first.
    static let limit = 300

    /// How much smaller than a screen needs a backdrop already loaded may be and still be used: 15%, too little to see
    /// on a backdrop, where asking again would load the whole image a second time.
    static let tolerance: CGFloat = 1.15

    private static var tints: [String: Color] = [:]
    private static var widths: [String: CGFloat] = [:]
    private static var order: [String] = []

    // MARK: - Tints

    /// The tint last taken from the backdrop of the item with `itemID`, if any.
    static func tint(for itemID: String) -> Color? {
        tints[itemID]
    }

    /// Remembers the tint taken from the backdrop of the item with `itemID`.
    static func remember(_ tint: Color, for itemID: String) {
        tints[itemID] = tint
        touch(itemID)
    }

    // MARK: - Backdrop widths

    /// The width, in points, to ask for the backdrop of the item with `itemID` so that it fills `size`, or zero until
    /// `size` is known.
    ///
    /// When the backdrop has already been asked for at a width at most ``tolerance`` smaller than `size` needs, or any
    /// larger, that width is used again, so the image comes from memory. Otherwise the width `size` needs is
    /// remembered and returned. Home's hero and the detail screen size their heroes alike but not always to the
    /// point, as while the detail screen zooms in, so this keeps both on one image.
    static func backdropWidth(for itemID: String, filling size: CGSize) -> CGFloat {
        let needed = HomeHeroPage.backdropWidth(for: size)
        guard needed > 0 else { return 0 }
        if let asked = widths[itemID], asked * tolerance >= needed {
            return asked
        }
        widths[itemID] = needed
        touch(itemID)
        return needed
    }

    // MARK: - Helpers

    /// Marks `itemID` as the most recent, forgetting the oldest item once there are more than ``limit``.
    private static func touch(_ itemID: String) {
        order.removeAll { $0 == itemID }
        order.append(itemID)
        while order.count > limit {
            let oldest = order.removeFirst()
            tints[oldest] = nil
            widths[oldest] = nil
        }
    }

    #if DEBUG
        /// Forgets everything, for tests.
        static func forgetAll() {
            tints = [:]
            widths = [:]
            order = []
        }
    #endif
}
