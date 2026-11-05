import QuartzCore

/// One character on stage: its face as it stands before a move, with its face
/// as it lands over it, which comes up as it travels.
final class PieceLayer: StillLayer {
    /// Slate.
    let before = TextLayer()
    /// Bone when it lands in the answer; slate in working.
    let after = TextLayer()
    /// The two faces are different glyphs, as when a letter changes case on
    /// the way, so the first goes as the second comes. Otherwise the second
    /// simply covers it.
    var morphs = false
    /// Set while a journey or fade is running as an animation, so later
    /// frames leave it be.
    private(set) var animating = false

    override init() {
        super.init()
        addSublayer(before)
        addSublayer(after)
        after.opacity = 0
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// In its first place, not moving yet. One that will fade in waits
    /// unseen, in its landing face.
    func wait(at point: CGPoint, opacity: Double, faded: Bool) {
        settle(at: point, progress: faded ? 1 : 0, opacity: opacity)
    }

    /// In its last place, or gone if it faded out.
    func land(at point: CGPoint, opacity: Double) {
        settle(at: point, progress: 1, opacity: opacity)
    }

    /// Partway, placed by hand: before a journey's animation can run, as
    /// when a surface is mounted mid-cue.
    func step(to point: CGPoint, progress: Double, opacity: Double) {
        settle(at: point, progress: progress, opacity: opacity)
    }

    private func settle(at point: CGPoint, progress: Double, opacity: Double) {
        removeAllAnimations()
        after.removeAllAnimations()
        before.removeAllAnimations()
        animating = false
        position = point
        after.opacity = Float(progress)
        before.opacity = morphs ? Float(1 - progress) : 1
        self.opacity = Float(opacity)
    }

    /// Sets off along its arc, already `elapsed` seconds in if the clock has
    /// run on since it was due, brightening or dimming on the way if it is
    /// joining or leaving the unused letters.
    func travel(along arc: Arc, from leaving: Double, to arriving: Double, elapsed: Double, duration: Double) {
        guard !animating else { return }
        animating = true
        let begin = convertTime(CACurrentMediaTime(), from: nil) - max(0, elapsed)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = arc.path
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let arrive = CABasicAnimation(keyPath: "opacity")
        arrive.fromValue = 0
        arrive.toValue = 1
        var animations = [(move as CAAnimation, self as CALayer, "travel"), (arrive, after, "arrive")]
        if morphs {
            let leave = CABasicAnimation(keyPath: "opacity")
            leave.fromValue = 1
            leave.toValue = 0
            animations.append((leave, before, "leave"))
            before.opacity = 0
        }
        if leaving != arriving {
            let dim = CABasicAnimation(keyPath: "opacity")
            dim.fromValue = leaving
            dim.toValue = arriving
            animations.append((dim, self, "dim"))
        }
        for (animation, layer, key) in animations {
            animation.beginTime = begin
            animation.duration = duration
            animation.fillMode = .backwards
            layer.add(animation, forKey: key)
        }
        opacity = Float(arriving)
        position = arc.end
        after.opacity = 1
    }

    /// Fades out where it stands, or in where it lands, to `opacity`.
    func fade(in fadingIn: Bool, at point: CGPoint, to opacity: Double, elapsed: Double, duration: Double) {
        guard !animating else { return }
        animating = true
        position = point
        after.opacity = fadingIn ? 1 : 0
        before.opacity = fadingIn && morphs ? 0 : 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fadingIn ? 0 : opacity
        fade.toValue = fadingIn ? opacity : 0
        fade.beginTime = convertTime(CACurrentMediaTime(), from: nil) - max(0, elapsed)
        fade.duration = duration
        fade.fillMode = .backwards
        add(fade, forKey: "fade")
        self.opacity = fadingIn ? Float(opacity) : 0
    }
}

/// A letter's way from one place to another: a quadratic curve that bows
/// up when it heads right and down when it heads left.
struct Arc {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Where the letter is when it is `p` of the way through its time,
    /// eased in and out as the animation is.
    func point(at p: Double) -> CGPoint {
        let t = CGFloat(p * p * (3 - 2 * p)), u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
}
