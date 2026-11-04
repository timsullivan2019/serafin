import JellyfinAPI
import Nuke
import NukeUI
import SerafinCore
import SerafinDesign
import SwiftUI

/// Loads an item's artwork for one role and hands it to `content`: from the server through the shared pipeline, from
/// the device for an item shown from what was saved with its download, or the generated art for the samples.
///
/// The server is asked for an image as wide as `content` is laid out, or `width` when given, and a saved picture is
/// decoded no wider. Until the artwork arrives, `content` gets nil and draws its placeholder.
struct ItemArtwork<Content: View>: View {
    private let item: MediaItem
    private let role: ImageRole
    private let fixedWidth: CGFloat?
    private let onLoad: (@MainActor @Sendable (CGImage) -> Void)?
    private let content: (Image?) -> Content
    @Environment(\.artwork) private var artwork
    @Environment(\.displayScale) private var scale
    @State private var measuredWidth: CGFloat = 0

    /// Loads artwork.
    ///
    /// - Parameters:
    ///   - item: The item.
    ///   - role: Where the artwork is drawn.
    ///   - width: The width to ask for, in points, when it differs from the content's, as for a logo.
    ///   - onLoad: Called with the image once it has loaded, for deriving the screen's tint.
    ///   - content: Draws the artwork, or a placeholder for nil.
    init(
        _ item: MediaItem,
        role: ImageRole,
        width: CGFloat? = nil,
        onLoad: (@MainActor @Sendable (CGImage) -> Void)? = nil,
        @ViewBuilder content: @escaping (Image?) -> Content
    ) {
        self.item = item
        self.role = role
        self.fixedWidth = width
        self.onLoad = onLoad
        self.content = content
    }

    var body: some View {
        if let artwork, item.isSaved || item.source != nil {
            LazyImage(request: request(from: artwork)) { state in
                content(state.image)
            }
            .pipeline(artwork.pipeline)
            .onCompletion { [onLoad] result in
                if let onLoad, let image = try? result.get().image.bitmap {
                    onLoad(image)
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                measuredWidth = $0
            }
        } else {
            content(sampleImage)
        }
    }

    /// The request once the width is known, so the first request is already the right size: for the picture saved
    /// with the item's download when it's shown from that, otherwise for the server's.
    private func request(from artwork: Artwork) -> ImageRequest? {
        let width = fixedWidth ?? measuredWidth
        guard width > 0 else { return nil }
        if let saved = item.savedArtwork {
            return saved.url(for: role).map { Artwork.request(file: $0, width: width, scale: scale) }
        }
        return item.source.flatMap { artwork.request(role, of: $0, width: width, scale: scale) }
    }

    private var sampleImage: Image? {
        switch role {
        case .poster: MockMedia.posterImage(for: item.card)
        case .landscape, .backdrop, .watching: MockMedia.backdropImage(for: item.card)
        case .logo: nil
        }
    }
}

/// Loads a cast or crew member's photo and hands it to `content`.
struct PersonPhoto<Content: View>: View {
    let person: CastMember
    @ViewBuilder let content: (Image?) -> Content
    @Environment(\.artwork) private var artwork
    @Environment(\.displayScale) private var scale
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        if let artwork, let source = person.source {
            LazyImage(
                request: measuredWidth > 0 ? artwork.request(person: source, width: measuredWidth, scale: scale) : nil
            ) {
                content($0.image)
            }
            .pipeline(artwork.pipeline)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                measuredWidth = $0
            }
        } else {
            content(nil)
        }
    }
}

extension PlatformImage {
    /// The image's bitmap, for deriving a tint.
    var bitmap: CGImage? {
        #if canImport(UIKit)
            cgImage
        #else
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}
