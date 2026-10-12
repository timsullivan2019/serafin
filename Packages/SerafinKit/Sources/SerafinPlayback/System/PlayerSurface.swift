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
        /// Black corners over the picture's corners while Picture in Picture hands the video back. See
        /// ``roundCornersForHandBack(radius:)``.
        private(set) var handBackCorners: [CAShapeLayer] = []
        private var handBackCornerRadius: CGFloat = 0

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
            playerLayer.frame = bounds
            placeHandBackCorners()
            CATransaction.commit()
        }

        /// Rounds all four of the picture's corners in black, the way Picture in Picture's window has its top ones,
        /// while the window hands the video back into this view.
        ///
        /// The window flies into the picture with its top corners rounded and keeps them until it gives the video
        /// back, so the picture showed them for a few frames and then snapped square. With the same corners on the
        /// picture underneath, it keeps the window's shape as it takes over, and ``squareCornersAfterHandBack(reduceMotion:)``
        /// then squares them in a short animation. The bottom corners are rounded too, so all four square off together;
        /// the window lands with its own bottom corners square, so those round as it hands over. Until then they're black
        /// on the black around the picture, so they show nothing.
        ///
        /// - Parameter radius: The window's corner radius.
        func roundCornersForHandBack(radius: CGFloat) {
            removeHandBackCorners()
            guard radius > 0 else { return }
            handBackCornerRadius = radius
            for corner in [UIRectCorner.topLeft, .topRight, .bottomLeft, .bottomRight] {
                let cap = CAShapeLayer()
                cap.fillColor = UIColor.black.cgColor
                // Each shrinks into its own corner of the picture.
                cap.anchorPoint = CGPoint(
                    x: corner == .topLeft || corner == .bottomLeft ? 0 : 1,
                    y: corner == .topLeft || corner == .topRight ? 0 : 1)
                cap.path = Self.cornerPath(radius: radius, corner: corner)
                layer.addSublayer(cap)
                handBackCorners.append(cap)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placeHandBackCorners()
            CATransaction.commit()
        }

        /// Squares the picture's corners once Picture in Picture has handed the video back, shrinking the black corners
        /// into the picture's corners, or fading them with Reduce Motion.
        ///
        /// - Parameter reduceMotion: Whether Reduce Motion is on.
        func squareCornersAfterHandBack(reduceMotion: Bool) {
            let corners = handBackCorners
            handBackCorners = []
            guard !corners.isEmpty else { return }
            let duration = reduceMotion ? 0.2 : 0.3
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1))
            for cap in corners {
                if reduceMotion {
                    cap.opacity = 0
                } else {
                    cap.transform = CATransform3DMakeScale(0.01, 0.01, 1)
                }
            }
            CATransaction.commit()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration + 0.1))
                corners.forEach { $0.removeFromSuperlayer() }
            }
        }

        /// Takes the black corners away at once, as when the hand-back doesn't finish or the screen goes.
        func removeHandBackCorners() {
            handBackCorners.forEach { $0.removeFromSuperlayer() }
            handBackCorners = []
        }

        /// Puts the black corners on the picture's corners, where Picture in Picture's window lands. A picture that fills
        /// the view has its corners off screen, so they're hidden then.
        private func placeHandBackCorners() {
            guard !handBackCorners.isEmpty else { return }
            let picture = playerLayer.videoRect
            let size = Self.cornerExtent(radius: handBackCornerRadius)
            let fits =
                !picture.isEmpty && bounds.insetBy(dx: -1, dy: -1).contains(picture)
                && picture.width > size * 2 && picture.height > size * 2
            for cap in handBackCorners {
                cap.isHidden = !fits
                cap.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                cap.position = CGPoint(
                    x: cap.anchorPoint.x == 0 ? picture.minX : picture.maxX,
                    y: cap.anchorPoint.y == 0 ? picture.minY : picture.maxY)
            }
        }

        /// How big the black outside a corner of `radius` is: a quarter circle a little tighter than the radius, which
        /// follows the continuous corner of Picture in Picture's window to within a pixel.
        static func cornerExtent(radius: CGFloat) -> CGFloat {
            radius * 0.92
        }

        /// The black outside a rounded `corner` of `radius`: a square as big as the corner, less a quarter circle.
        /// Drawn as one shape, so no edge runs through the picture.
        static func cornerPath(radius: CGFloat, corner: UIRectCorner) -> CGPath {
            let size = cornerExtent(radius: radius)
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: size, y: 0))
            path.addArc(
                center: CGPoint(x: size, y: size), radius: size, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            path.closeSubpath()
            guard corner != .topLeft else { return path }
            // The same, mirrored across to the corner asked for.
            let flipsAcross = corner == .topRight || corner == .bottomRight
            let flipsDown = corner == .bottomLeft || corner == .bottomRight
            var mirror = CGAffineTransform(
                a: flipsAcross ? -1 : 1, b: 0, c: 0, d: flipsDown ? -1 : 1, tx: flipsAcross ? size : 0,
                ty: flipsDown ? size : 0)
            return path.copy(using: &mirror) ?? path
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
