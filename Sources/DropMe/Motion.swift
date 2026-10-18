import AppKit

/// Small, restrained animations. With “Reduce motion” only the cross-fades remain.
extension NSView {
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Dynamic colors (labelColor …) resolved for the current appearance as CGColor.
    func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    /// Sets a layer property and animates there from the currently visible value.
    func animate(_ layer: CALayer?, key: String, to value: Any?, duration: CFTimeInterval, set: (CALayer) -> Void) {
        guard let layer else { return }
        let from = (layer.presentation() ?? layer).value(forKeyPath: key)
        set(layer)
        guard duration > 0, window != nil else { return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }

    /// Cross-fades the next change of content or visibility.
    func crossfade(_ layer: CALayer?, duration: CFTimeInterval) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        layer?.add(transition, forKey: "crossfade")
    }

    /// Scale around the center; AppKit puts the layer's anchor point at the bottom left corner.
    func centeredScale(_ scale: CGFloat) -> CATransform3D {
        let b = bounds
        return CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                   CATransform3DMakeTranslation(b.width * (1 - scale) / 2, b.height * (1 - scale) / 2, 0))
    }

    /// Springs back to 100 % from a slightly different size.
    func pop(from scale: CGFloat) {
        guard let layer, window != nil, !reduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = centeredScale(scale)
        spring.toValue = CATransform3DIdentity
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 22
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }
}
