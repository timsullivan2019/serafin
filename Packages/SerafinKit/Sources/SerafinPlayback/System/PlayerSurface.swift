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
        /// Where the picture is in a hand-back from Picture in Picture inside the app. See ``hideForHandBack()``.
        enum HandBack: Equatable {
            /// No hand-back: the picture fills the view and shows.
            case none
            /// Shrunk to nothing in the view's middle, so Picture in Picture has no picture to fly its window into.
            case hidden
            /// Back to full size, still clear, until the video is back.
            case waiting
        }

        /// The layer showing the video.
        public let playerLayer = AVPlayerLayer()
        /// Whether the picture fills the view, cropping what spills past its edges, rather than fitting inside it.
        public private(set) var fillsBounds = false
        /// Where the picture is in a hand-back from Picture in Picture.
        private(set) var handBack = HandBack.none
        /// The key of the animation fading the picture in after a hand-back.
        static let fadeInKey = "fadeInAfterHandBack"

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
            playerLayer.frame = pictureFrame
            CATransaction.commit()
        }

        /// Takes the picture away while Picture in Picture hands the video back inside the app.
        ///
        /// Picture in Picture flies its window into the picture it hands the video to, and inside the app iOS rounds
        /// the window's corners to match the screen's as it lands there, as wide as the screen in portrait. With no
        /// picture to fly into, the window shrinks away where it is instead. The picture comes back to full size once
        /// iOS has looked for it (``layOutAfterHandBack()``), and fades in once the video is back
        /// (``showAfterHandBack()``).
        func hideForHandBack() {
            playerLayer.removeAnimation(forKey: Self.fadeInKey)
            handBack = .hidden
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.opacity = 0
            playerLayer.frame = pictureFrame
            CATransaction.commit()
        }

        /// Puts the picture back to full size, still clear, once Picture in Picture has looked for it.
        func layOutAfterHandBack() {
            guard handBack == .hidden else { return }
            handBack = .waiting
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = pictureFrame
            CATransaction.commit()
        }

        /// Fades the picture in at full size once Picture in Picture has handed the video back.
        func showAfterHandBack() {
            guard handBack != .none else { return }
            handBack = .none
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = pictureFrame
            playerLayer.opacity = 1
            CATransaction.commit()
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            playerLayer.add(fade, forKey: Self.fadeInKey)
        }

        /// Shows the picture at full size at once, as when the hand-back doesn't finish or the screen goes.
        func cancelHandBack() {
            playerLayer.removeAnimation(forKey: Self.fadeInKey)
            guard handBack != .none else { return }
            handBack = .none
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = pictureFrame
            playerLayer.opacity = 1
            CATransaction.commit()
        }

        /// Where the video layer goes: the whole view, or nothing in its middle while it's hidden for a hand-back.
        private var pictureFrame: CGRect {
            handBack == .hidden ? CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0) : bounds
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
