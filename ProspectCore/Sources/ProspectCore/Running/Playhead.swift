import Foundation

/// What the operator is driving: the cue on stage, what GO will do next, and
/// any cue number being typed.
///
/// Only `go`, a continue, `rerun` and `resume` put anything on stage, and each
/// returns a `Fire` for the app to act on. Everything else only moves what
/// stands by. Cues are tracked by `id`, so editing the sheet can't make the
/// playhead point at a different cue.
///
/// A cue can wait partway for GO, as an anagram cue's working can. Each of
/// those GO points is a step of the cue, and the sheet reads as rows: each
/// cue, then its steps. Any row can stand by. GO on a step of the live cue
/// carries it on there, or jumps straight there, forward or back; GO on a
/// step of another cue fires that cue at that step, with the steps before it
/// already done. The arrows move a row at a time, through every cue's steps.
public struct Playhead: Equatable, Sendable {
    /// The cue on stage. Nil until the first GO.
    public private(set) var live: UUID?
    /// The cue GO acts on: fired, or for a step of the live cue, carried on.
    /// Nil at the end of the sheet, or when it's empty.
    public private(set) var standby: UUID?
    /// The step of the standby cue that stands by, when one does: its GO
    /// point, counted from 0. Nil for the cue itself, fired from its start.
    public private(set) var standbyStep: Int?
    /// Digits typed toward a cue number, shown in the standby panel.
    public private(set) var entry = ""
    /// The override the operator toggles when something has gone wrong. It
    /// stays on across cues until toggled back.
    public var blackout = false

    /// How many GO points the live cue has, and how many it has reached: a
    /// GO to point k reaches k + 1 of them.
    public private(set) var goPoints = 0
    public private(set) var goPointsTaken = 0

    /// The longest number the keypad entry accepts.
    public static let entryLimit = 8

    /// A show opens with nothing on stage and its first cue standing by.
    public init(show: Show) {
        standby = show.cues.first?.id
    }

    public struct Fire: Equatable, Sendable {
        public enum Presentation: Equatable, Sendable {
            /// From the start: hold, then resolve. With a step, from that
            /// step, the steps before it already done.
            case run
            /// Straight to the finished state. Used to resume after a crash.
            case settled
            /// The live cue on from where it is: to its next GO point, or
            /// with a step, straight to that one, forward or back. Nothing
            /// changes cue.
            case carryOn
        }

        public let cue: UUID
        public let presentation: Presentation
        /// Fired by the cue before it continuing, not by the operator.
        public let automatic: Bool
        /// The GO point it starts at, or jumps to. Nil for the cue's start,
        /// or for carrying on to its next GO point.
        public let step: Int?

        public init(cue: UUID, presentation: Presentation, automatic: Bool, step: Int? = nil) {
            self.cue = cue
            self.presentation = presentation
            self.automatic = automatic
            self.step = step
        }
    }

    // MARK: Firing

    /// GO: act on what stands by, and stand by the row after it. Any entry
    /// in progress is discarded. Nil at the end of the sheet.
    public mutating func go(in show: Show) -> Fire? {
        entry = ""
        guard let id = standby, show.index(of: id) != nil else { return nil }
        if id == live, let step = standbyStep {
            // The live cue's own step: on to it, or straight to it.
            let next = step == goPointsTaken
            goPointsTaken = step + 1
            standByRow(after: id, step: step, in: show)
            return Fire(cue: id, presentation: .carryOn, automatic: false, step: next ? nil : step)
        }
        return fire(id, in: show, presentation: .run, automatic: false, step: standbyStep)
    }

    /// Call when the live cue settles. If it continues when finished with
    /// no wait, the next cue in the sheet fires now; a wait is timed by
    /// whoever keeps the clock, from this moment. A settle from a cue that is
    /// no longer live is ignored.
    public mutating func liveCueSettled(_ id: UUID, in show: Show) -> Fire? {
        guard let cue = show[id], cue.continueMode == .whenFinished(waitMs: 0) else { return nil }
        return continueAfter(id, in: show)
    }

    /// The show moves on by itself from `id`, as its Continue says: the next
    /// cue in the sheet fires. Nil if `id` is no longer live, or is last.
    public mutating func continueAfter(_ id: UUID, in show: Show) -> Fire? {
        guard id == live, let i = show.index(of: id), i + 1 < show.cues.count else { return nil }
        return fire(show.cues[i + 1].id, in: show, presentation: .run, automatic: true, step: nil)
    }

    /// R: run the live cue again from the start. What stands by is
    /// unchanged, but a cue with GO points has its first standing by again.
    public mutating func rerun(in show: Show) -> Fire? {
        guard let live else { return nil }
        goPoints = points(of: live, in: show)
        goPointsTaken = 0
        if goPoints > 0 {
            standby = live
            standbyStep = 0
        }
        return Fire(cue: live, presentation: .run, automatic: false)
    }

    /// Edit mode: runs the cue standing by on the stage, from the start, and
    /// leaves it standing by, so the cue being edited stays selected.
    public mutating func runStandby(in show: Show) -> Fire? {
        entry = ""
        // With nothing standing by, as after the last cue has gone, the live
        // cue is the one selected.
        guard let id = standby ?? live, show.index(of: id) != nil else { return nil }
        let saved = (standby ?? id, standby == nil ? nil : standbyStep)
        let fired = fire(id, in: show, presentation: .run, automatic: false, step: nil)
        (standby, standbyStep) = saved
        return fired
    }

    /// After a crash: put `id` up in its finished state and stand by the next.
    public mutating func resume(at id: UUID, in show: Show) -> Fire? {
        guard show.index(of: id) != nil else { return nil }
        entry = ""
        return fire(id, in: show, presentation: .settled, automatic: false, step: nil)
    }

    private mutating func fire(_ id: UUID, in show: Show, presentation: Fire.Presentation, automatic: Bool, step: Int?) -> Fire {
        live = id
        goPoints = points(of: id, in: show)
        if presentation == .run {
            goPointsTaken = step.map { $0 + 1 } ?? 0
            standByRow(after: id, step: step, in: show)
        } else {
            // Put up finished: every step done, and the next cue stands by.
            goPointsTaken = goPoints
            standByRow(after: id, step: goPoints > 0 ? goPoints - 1 : nil, in: show)
        }
        return Fire(cue: id, presentation: presentation, automatic: automatic, step: step)
    }

    /// The live cue was put up finished, as an edit in edit mode does, so
    /// every step of it is done and it waits for nothing: a step of it that
    /// stood by gives way to the next cue. Its steps can still be stood by
    /// again, to go back to.
    public mutating func liveCueRedrawn(in show: Show) {
        guard let live else { return }
        goPoints = points(of: live, in: show)
        goPointsTaken = goPoints
        if standby == live, standbyStep != nil { standByRow(after: live, step: goPoints > 0 ? goPoints - 1 : nil, in: show) }
    }

    // MARK: Rows

    /// How many steps a cue has: its GO points, with the settings it runs with.
    private func points(of id: UUID, in show: Show) -> Int {
        show[id]?.goPoints().count ?? 0
    }

    /// The row after a cue, or after one of its steps: its next step, or the
    /// next cue. Nil past the end of the sheet.
    private func row(after id: UUID, step: Int?, in show: Show) -> (cue: UUID, step: Int?)? {
        let next = (step ?? -1) + 1
        if next < points(of: id, in: show) { return (id, next) }
        guard let i = show.index(of: id), i + 1 < show.cues.count else { return nil }
        return (show.cues[i + 1].id, nil)
    }

    /// The row before a cue, or before one of its steps: its previous step,
    /// the cue itself, or the last step of the cue before. Nil at the top.
    private func row(before id: UUID, step: Int?, in show: Show) -> (cue: UUID, step: Int?)? {
        if let step { return (id, step > 0 ? step - 1 : nil) }
        guard let i = show.index(of: id), i > 0 else { return nil }
        let previous = show.cues[i - 1].id, n = points(of: previous, in: show)
        return (previous, n > 0 ? n - 1 : nil)
    }

    private mutating func standByRow(after id: UUID, step: Int?, in show: Show) {
        let next = row(after: id, step: step, in: show)
        standby = next?.cue
        standbyStep = next?.step
    }

    // MARK: Standing by

    /// → ↓ PageDown: the next row, a cue's steps included. From the last row
    /// this reaches the end of the sheet.
    public mutating func standByNext(in show: Show) {
        entry = ""
        guard let id = standby, show.index(of: id) != nil else { return }
        standByRow(after: id, step: standbyStep, in: show)
    }

    /// ← ↑ PageUp: the row before. From the end of the sheet this reaches the
    /// last row; from the first cue it stays.
    public mutating func standByPrevious(in show: Show) {
        entry = ""
        guard let id = standby, show.index(of: id) != nil else {
            guard let last = show.cues.last?.id else { return }
            let n = points(of: last, in: show)
            standby = last
            standbyStep = n > 0 ? n - 1 : nil
            return
        }
        guard let previous = row(before: id, step: standbyStep, in: show) else { return }
        standby = previous.cue
        standbyStep = previous.step
    }

    /// A click on a cue in the list.
    public mutating func standBy(_ id: UUID) {
        entry = ""
        standby = id
        standbyStep = nil
    }

    /// A click on one of a cue's steps. A step the cue doesn't have stands
    /// by the cue itself.
    public mutating func standBy(_ id: UUID, step: Int, in show: Show) {
        standBy(id)
        if step >= 0, step < points(of: id, in: show) { standbyStep = step }
    }

    /// The Go-to field, which also reaches numbers with letters in them.
    /// False if no cue has that number.
    public mutating func standBy(number: String, in show: Show) -> Bool {
        guard let i = show.index(ofNumber: number) else { return false }
        standBy(show.cues[i].id)
        return true
    }

    // MARK: Keypad entry

    /// 0–9 and `.`. Anything else is ignored.
    public mutating func type(_ c: Character) {
        guard c.isASCII, c.isNumber || c == ".", entry.count < Self.entryLimit else { return }
        entry.append(c)
    }

    /// Backspace.
    public mutating func deleteBackward() {
        if !entry.isEmpty { entry.removeLast() }
    }

    /// Escape.
    public mutating func clearEntry() {
        entry = ""
    }

    public enum EntryResult: Equatable, Sendable {
        case empty
        case stoodBy(UUID)
        case noSuchCue(String)
    }

    /// Return: stand by the cue whose number was typed. The entry clears
    /// either way.
    public mutating func commitEntry(in show: Show) -> EntryResult {
        let typed = entry
        entry = ""
        guard !typed.isEmpty else { return .empty }
        guard let i = show.index(ofNumber: typed) else { return .noSuchCue(typed) }
        standBy(show.cues[i].id)
        return .stoodBy(show.cues[i].id)
    }

    // MARK: Video arming

    /// The cues that could fire next: the standby cue, and the cue after the
    /// live one if the live one continues. Video cues among them should be
    /// armed now, not when the live cue settles.
    public func cuesThatMayFireNext(in show: Show) -> [UUID] {
        var ids: [UUID] = []
        if let live, let i = show.index(of: live), i + 1 < show.cues.count, show.cues[i].continueMode.continues {
            ids.append(show.cues[i + 1].id)
        }
        if let standby, show.index(of: standby) != nil, !ids.contains(standby) {
            ids.append(standby)
        }
        return ids
    }

    // MARK: Edits

    /// After the sheet has been edited: if the standby cue was deleted, stand
    /// by whichever cue now occupies its place. If the live cue was deleted,
    /// nothing is live; the stage takes it off.
    public mutating func reconcile(from old: Show, to new: Show) {
        if let id = live, new.index(of: id) == nil {
            live = nil
            goPoints = 0
            goPointsTaken = 0
        }
        // A step the edited cue no longer has: the cue itself stands by.
        if let id = standby, let step = standbyStep, step >= points(of: id, in: new) { standbyStep = nil }
        guard let id = standby, new.index(of: id) == nil else { return }
        standbyStep = nil
        guard let oldIndex = old.index(of: id) else {
            standby = new.cues.first?.id
            return
        }
        // The first surviving cue at or after the deleted one's place.
        standby = old.cues[oldIndex...].lazy.compactMap { new[$0.id]?.id }.first
    }
}
