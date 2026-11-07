import Foundation

/// A place partway through a cue where it waits for GO, as an anagram cue's
/// working can, or a morph cue before each stage. GO carries the cue on rather than firing the next one.
public struct GoPoint: Equatable, Sendable {
    public enum Unit: String, Sendable {
        case anagram, step, stage, stop, layer
    }

    /// What it is the GO for: an anagram's turn, a step of one, or a morph's
    /// stage.
    public var unit: Unit
    /// What GO brings on: the anagram whose turn it is, the step it moves
    /// to, or the picture a stage becomes.
    public var text: String
    /// The line or action the GO waits for, as a cue's own cue point. Empty
    /// when none is set.
    public var cuePoint: String

    public init(unit: Unit, text: String, cuePoint: String = "") {
        self.unit = unit
        self.text = text
        self.cuePoint = cuePoint
    }
}

extension Cue {
    /// Where this cue waits for GO partway, with the settings it runs with.
    /// Only anagram, morph and map cues ever do.
    public func goPoints() -> [GoPoint] {
        switch content {
        case .anagram(let c): c.goPoints(c.settings.advance)
        case .morph(let c): c.goPoints(eachStageOnGO: c.settings.eachStageOnGO)
        case .map(let c): c.goPoints(eachStopOnGO: c.settings.eachStopOnGO)
        case .layered(let c): c.goPoints(eachStepOnGO: c.settings.eachStepOnGO)
        case .keypad(let c): c.goPoints()
        default: []
        }
    }

    /// Sets the cue point of GO point `point`, as the settings have it, on
    /// what that GO belongs to: the step an anagram's GO moves to, the
    /// picture a morph's stage becomes, the stop a map's dot leaves for.
    /// Empty clears it.
    public mutating func setCuePoint(_ line: String, ofGoPoint point: Int) {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        switch content {
        case .anagram(var c):
            // Each GO, as the anagram and the step it moves to.
            var targets: [(anagram: Int, step: String)] = []
            for (i, a) in c.anagrams.enumerated() where a.isSolvedOnStage {
                switch c.settings.advance {
                case .byItself: break
                case .eachAnagram: targets.append((i, a.steps[1]))
                case .eachStep: targets += a.steps.dropFirst().map { (i, $0) }
                }
            }
            guard targets.indices.contains(point) else { return }
            let (i, step) = targets[point]
            c.anagrams[i].cuePoints[step] = line.isEmpty ? nil : line
            content = .anagram(c)
        case .morph(var c):
            guard c.settings.eachStageOnGO, c.pictures.indices.contains(point + 1) else { return }
            c.pictures[point + 1].cuePoint = line
            content = .morph(c)
        case .map(var c):
            let stops = Array(c.stops.dropFirst())
            guard c.settings.eachStopOnGO, stops.indices.contains(point) else { return }
            var stop = c.stop(at: stops[point])
            stop.cuePoint = line
            c.route[stops[point]].stop = stop
            content = .map(c)
        case .layered(var c):
            guard c.settings.eachStepOnGO else { return }
            c.setCuePoint(line, ofStep: point)
            content = .layered(c)
        default:
            return
        }
    }

    /// Whether any GO of this cue has a cue point of its own.
    var hasGoCuePoints: Bool {
        switch content {
        case .anagram(let c): c.anagrams.contains { !$0.cuePoints.isEmpty }
        case .morph(let c): c.pictures.contains { !$0.cuePoint.isEmpty }
        case .map(let c): c.route.contains { !($0.stop?.cuePoint.isEmpty ?? true) }
        case .layered(let c): c.hasGoCuePoints
        default: false
        }
    }
}
