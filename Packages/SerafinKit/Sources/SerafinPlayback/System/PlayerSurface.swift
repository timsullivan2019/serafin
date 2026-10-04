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

        /// Gives the video view back, unless a newer screen has taken it already.
        func release() {
            defer { engine = nil }
            guard let engine, engine.videoView.superview === self else { return }
            engine.videoView.removeFromSuperview()
            engine.surfaceDisappeared()
        }
    }

    /// A view that shows an `AVPlayerLayer` filling its bounds, with the picture fitted inside.
    public final class PlayerLayerView: UIView {
        /// The layer showing the video.
        public let playerLayer = AVPlayerLayer()

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

        override public func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
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
