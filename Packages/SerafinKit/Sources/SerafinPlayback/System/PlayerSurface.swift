#if canImport(UIKit)
    import AVKit
    import SwiftUI

    /// The video picture for the player screen. It also gives the engine the layer Picture in Picture needs, so
    /// leaving the app while something plays carries on in a floating window.
    public struct PlayerSurface: UIViewRepresentable {
        private let engine: PlayerEngine

        /// Creates the surface for `engine`'s player.
        public init(engine: PlayerEngine) {
            self.engine = engine
        }

        public func makeUIView(context: Context) -> PlayerLayerView {
            let view = PlayerLayerView()
            view.playerLayer.player = engine.player
            engine.attachPictureInPicture(to: view.playerLayer)
            return view
        }

        public func updateUIView(_ view: PlayerLayerView, context: Context) {
            if view.playerLayer.player !== engine.player {
                view.playerLayer.player = engine.player
            }
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
