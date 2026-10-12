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
        /// A second layer of the same video under the main one, which shows only while Picture in Picture hands the
        /// video back. See ``fillHandBack(from:)``.
        let underlay = AVPlayerLayer()
        private var handBack: Task<Void, Never>?

        /// The player whose video the view shows, or nil while the view lets go of it, as in the background.
        public var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                // Always together: attached in the middle of a video, a layer can show an older frame, and letting go
                // of one can move a paused picture to another frame.
                underlay.player = newValue
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
            underlay.videoGravity = .resizeAspect
            underlay.opacity = 0
            layer.addSublayer(underlay)
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
            underlay.videoGravity = playerLayer.videoGravity
            CATransaction.commit()
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            underlay.frame = bounds
            CATransaction.commit()
        }

        /// Shows the picture under the main layer from `delay` on, while Picture in Picture hands the video back into
        /// this view.
        ///
        /// Picture in Picture's window flies into the picture with its top corners rounded, and keeps them until it
        /// gives the video back, a moment after it lands. The main layer shows nothing while Picture in Picture has
        /// the video, so the corners showed the black behind as notches in the picture. The picture underneath fills
        /// them. It fades in only as the window lands, so it never shows beside the window in flight.
        ///
        /// - Parameter delay: How long the window takes to all but land.
        func fillHandBack(from delay: Duration) {
            handBack?.cancel()
            handBack = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.08)
                underlay.opacity = 1
                CATransaction.commit()
            }
        }

        /// Hides the picture under the main layer after `delay`, by which time the main layer shows the video again.
        ///
        /// - Parameter delay: How long to keep it, or zero to hide it at once.
        func endHandBack(after delay: Duration = .zero) {
            handBack?.cancel()
            handBack = nil
            guard delay > .zero else {
                hideUnderlay()
                return
            }
            handBack = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.hideUnderlay()
            }
        }

        private func hideUnderlay() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            underlay.opacity = 0
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
