import AppKit

/// Kleine, zurückhaltende Animationen. Bei „Bewegung reduzieren“ bleibt nur das Überblenden.
extension NSView {
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Dynamische Farben (labelColor …) passend zum aktuellen Erscheinungsbild als CGColor.
    func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    /// Setzt eine Ebeneneigenschaft und blendet vom aktuell sichtbaren Wert dorthin über.
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

    /// Blendet die nächste Änderung an Inhalt oder Sichtbarkeit weich über.
    func crossfade(_ layer: CALayer?, duration: CFTimeInterval) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        layer?.add(transition, forKey: "crossfade")
    }

    /// Skalierung um die Mitte; AppKit legt den Ankerpunkt der Ebene auf die Ecke unten links.
    func centeredScale(_ scale: CGFloat) -> CATransform3D {
        let b = bounds
        return CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                   CATransform3DMakeTranslation(b.width * (1 - scale) / 2, b.height * (1 - scale) / 2, 0))
    }

    /// Federt von einer leicht anderen Größe zurück auf 100 %.
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
