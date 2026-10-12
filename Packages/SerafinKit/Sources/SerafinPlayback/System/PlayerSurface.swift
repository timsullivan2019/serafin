#if canImport(UIKit)
    import AVKit
    import SwiftUI

    /// The video picture for the player screen.
    ///
    /// It hosts the engine's ``PlayerEngine/videoView``, which outlives the screen: leaving the app while something
    /// plays carries on in Picture in Picture, and the next player screen picks the picture back up.
    public struct PlayerSurface: UIViewRepresentable {
        private let engine: PlayerEngine

        /// Creates the surface for `engine`'s video.
        public init(engine: PlayerEngine) {
            self.engine = engine
        }

        public func makeUIView(context: Context) -> PlayerSurfaceView {
            let host = PlayerSurfaceView()
            host.show(engine)
            return host
        }

        public func updateUIView(_ host: PlayerSurfaceView, context: Context) {
            host.show(engine)
        }

        public static func dismantleUIView(_ host: PlayerSurfaceView, coordinator: ()) {
            host.release()
        }
    }

    /// Holds the engine's video view while a player screen shows it.
    public final class PlayerSurfaceView: UIView {
        private weak var engine: PlayerEngine?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        /// Takes the engine's video view, unless it is already here.
        func show(_ engine: PlayerEngine) {
            let video = engine.videoView
            guard video.superview !== self else { return }
            self.engine = engine
            video.frame = bounds
            video.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(video)
            engine.surfaceAppeared()
        }

        override public func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let engine, engine.videoView.superview === self else { return }
            engine.surfaceEnteredWindow()
        }

        /// Gives the video view back, unless a newer screen has taken it already.
        func release() {
            defer { engine = nil }
            guard let engine, engine.videoView.superview === self else { return }
            engine.videoView.removeFromSuperview()
            engine.surfaceDisappeared()
        }
    }

    /// A view that shows an `AVPlayerLayer` filling its bounds, with the picture fitted inside or filling it.
    public final class PlayerLayerView: UIView {
        /// The layer showing the video.
        public let playerLayer = AVPlayerLayer()
        /// Whether the picture fills the view, cropping what spills past its edges, rather than fitting inside it.
        public private(set) var fillsBounds = false
        /// How large the picture is, against the view, while Picture in Picture hands the video back, or 1 when it
        /// isn't. See ``landSmallerForHandBack(scale:)``.
        private(set) var handBackScale: CGFloat = 1
        /// The key of the animation growing the picture to full size after a hand-back.
        static let growKey = "growAfterHandBack"

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
            layer.addSublayer(playerLayer)
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        /// Fits the picture inside the view, with black bars where its shape differs, or fills the view, cropping
        /// its edges.
        ///
        /// - Parameters:
        ///   - fills: Whether the picture fills the view.
        ///   - animated: Whether the picture grows or shrinks into place, rather than jumping.
        public func setFillsBounds(_ fills: Bool, animated: Bool) {
            guard fills != fillsBounds else { return }
            fillsBounds = fills
            CATransaction.begin()
            CATransaction.setDisableActions(!animated)
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            playerLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
            CATransaction.commit()
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = Self.frame(bounds, scaledBy: handBackScale)
            CATransaction.commit()
        }

        /// Shrinks the picture about its middle while Picture in Picture hands the video back, so the window lands on a
        /// picture `scale` times its size.
        ///
        /// Handing back inside the app, iOS gives the window rounded corners as it lands, concentric with the screen's,
        /// when the picture it lands on is within the screen's corner radius of the screen's width or height. A
        /// picture fitted to the screen always is, so the window landed with its top corners rounded and squared them
        /// as it handed over. Landing on a picture that much smaller keeps every corner square, and
        /// ``growAfterHandBack()`` then grows it to full size. ``landingScale(pictureSize:screenSize:cornerRadius:)``
        /// works out the size.
        ///
        /// - Parameter scale: How large the picture lands, against its full size.
        func landSmallerForHandBack(scale: CGFloat) {
            cancelHandBackLanding()
            guard scale < 1 else { return }
            handBackScale = scale
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = Self.frame(bounds, scaledBy: scale)
            CATransaction.commit()
        }

        /// Grows the picture to full size once Picture in Picture has handed the video back, from the size the window
        /// landed at.
        func growAfterHandBack() {
            let scale = handBackScale
            guard scale < 1 else { return }
            handBackScale = 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
            // By its transform rather than its frame, so the picture keeps its place as it grows.
            let grow = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.15)
            grow.keyPath = "transform.scale"
            grow.fromValue = scale
            grow.toValue = 1
            grow.duration = grow.settlingDuration
            playerLayer.add(grow, forKey: Self.growKey)
        }

        /// Puts the picture back to full size at once, as when the hand-back doesn't finish or the screen goes.
        func cancelHandBackLanding() {
            playerLayer.removeAnimation(forKey: Self.growKey)
            guard handBackScale < 1 else { return }
            handBackScale = 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        /// How large a picture of `pictureSize` should be for Picture in Picture's window to land on it with square
        /// corners: small enough to stay the screen's corner radius short of the screen's width and height. 1 when it
        /// already is, and when it covers the screen, where the window's corners land past the screen's.
        ///
        /// - Parameters:
        ///   - pictureSize: The picture's full size.
        ///   - screenSize: The size of the screen.
        ///   - cornerRadius: The screen's corner radius.
        /// - Returns: How large the picture should be, against its full size.
        static func landingScale(pictureSize: CGSize, screenSize: CGSize, cornerRadius: CGFloat) -> CGFloat {
            guard cornerRadius > 0, pictureSize.width > 0, pictureSize.height > 0 else { return 1 }
            if pictureSize.width >= screenSize.width, pictureSize.height >= screenSize.height { return 1 }
            // A point to spare, since sizes round to the pixel.
            let shortfall = cornerRadius + 1
            let scale = min(
                1, (screenSize.width - shortfall) / pictureSize.width,
                (screenSize.height - shortfall) / pictureSize.height)
            // A layout this far off isn't one the player screen has, so it's left alone.
            return scale >= 0.5 ? scale : 1
        }

        /// `rect` shrunk by `scale` about its middle.
        private static func frame(_ rect: CGRect, scaledBy scale: CGFloat) -> CGRect {
            guard scale < 1 else { return rect }
            return rect.insetBy(dx: rect.width * (1 - scale) / 2, dy: rect.height * (1 - scale) / 2)
        }
    }

    /// The AirPlay button, which lists Apple TVs and AirPlay speakers nearby. It is the system's own control, so it
    /// shows the system's menu.
    public struct AirPlayButton: UIViewRepresentable {
        /// Creates the button.
        public init() {}

        public func makeUIView(context: Context) -> AVRoutePickerView {
            let picker = AVRoutePickerView()
            picker.prioritizesVideoDevices = true
            picker.tintColor = .white
            picker.activeTintColor = .white
            return picker
        }

        public func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
    }
#endif
