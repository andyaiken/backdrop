import Foundation

/// A group of cues: a heading such as Act One, holding what follows it in
/// the sheet up to the next heading at its own level or above, groups inside
/// it included.
///
/// Groups only organise the sheet. They live beside the cues rather than
/// among them, so GO, standby, the arrow keys, continues and numbering never
/// see them; each heading just remembers the cue it stands above.
public struct CueGroup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// How far in it sits: 0 outermost, 1 inside a group, and so on. A level
    /// deeper than the group above it allows is read as one step in.
    public var level: Int
    /// The cue it stands above: its first cue, or for a group with no cues
    /// of its own, the first after it. Nil at the end of the sheet.
    public var before: UUID?

    public init(id: UUID = UUID(), name: String, level: Int = 0, before: UUID?) {
        self.id = id
        self.name = name
        self.level = max(0, level)
        self.before = before
    }
}

/// One row of the sheet as it reads with its groups.
public enum OutlineRow: Equatable, Sendable {
    /// A heading, how many groups it is inside, and how many cues it holds,
    /// those in groups inside it included.
    case group(CueGroup, depth: Int, count: Int)
    /// A cue, and how many groups it is inside.
    case cue(Cue, depth: Int)
}

extension Show {
    /// The sheet as it reads: each heading where it stands, then the cues,
    /// each at the depth of the groups around it.
    public var outline: [OutlineRow] {
        var rows: [OutlineRow] = []
        var open: [(group: CueGroup, row: Int)] = []
        var counts: [Int: Int] = [:]
        func headings(before id: UUID?) {
            for group in groups where group.before == id || (id == nil && group.before.flatMap(index(of:)) == nil) {
                // A heading closes every group at its level or deeper.
                while let last = open.last, last.group.level >= group.level { open.removeLast() }
                open.append((group, rows.count))
                rows.append(.group(group, depth: open.count - 1, count: 0))
            }
        }
        for cue in cues {
            headings(before: cue.id)
            for o in open { counts[o.row, default: 0] += 1 }
            rows.append(.cue(cue, depth: open.count))
        }
        headings(before: nil)
        for (row, count) in counts {
            if case .group(let group, let depth, _) = rows[row] { rows[row] = .group(group, depth: depth, count: count) }
        }
        return rows
    }

    /// The groups a cue is in, outermost first.
    public func groups(around id: UUID) -> [CueGroup] {
        var open: [CueGroup] = []
        for row in outline {
            switch row {
            case .group(let group, let depth, _):
                open = Array(open.prefix(depth)) + [group]
            case .cue(let cue, let depth):
                if cue.id == id { return Array(open.prefix(depth)) }
            }
        }
        return []
    }

    /// After the cues have changed, as by a delete: a heading whose cue has
    /// gone stands above the next cue that is still there, or at the end of
    /// the sheet; and the headings are kept in the order they read.
    public mutating func tidyGroups(after old: Show) {
        for i in groups.indices {
            guard let id = groups[i].before, index(of: id) == nil else { continue }
            let from = old.index(of: id) ?? old.cues.count
            groups[i].before = old.cues[from...].first { index(of: $0.id) != nil }?.id
        }
        let places = groups.map { $0.before.flatMap(index(of:)) ?? cues.count }
        groups = groups.indices.sorted { (places[$0], $0) < (places[$1], $1) }.map { groups[$0] }
    }
}

// MARK: - Editing

extension Show {
    /// The rows a group covers in the outline: its heading, and everything
    /// up to the next heading at its level or above.
    public func span(of id: UUID) -> Range<Int>? {
        let rows = outline
        guard let start = rows.firstIndex(where: { if case .group(let g, _, _) = $0 { g.id == id } else { false } }),
              case .group(_, let depth, _) = rows[start] else { return nil }
        let end = rows[(start + 1)...].firstIndex { row in
            if case .group(_, let d, _) = row { d <= depth } else { false }
        } ?? rows.count
        return start..<end
    }

    /// The outline row a cue is on.
    public func row(of id: UUID) -> Int? {
        outline.firstIndex { if case .cue(let c, _) = $0 { c.id == id } else { false } }
    }

    /// Moves the outline rows `rows` to stand before row `target`, or at the
    /// end when `target` is the row count. The sheet is read back as show.json
    /// is: each heading stands above the cue that follows it. So a group's
    /// first cue dragged away leaves its heading where it was, and a cue
    /// dropped just under a heading joins that group. A drop inside the rows
    /// being moved changes nothing.
    public mutating func moveRows(_ rows: Range<Int>, before target: Int) {
        var entries = outline
        guard !rows.isEmpty, rows.upperBound <= entries.count, target >= 0, target <= entries.count,
              !(rows.lowerBound...rows.upperBound).contains(target) else { return }
        let moving = Array(entries[rows])
        entries.removeSubrange(rows)
        entries.insert(contentsOf: moving, at: target > rows.lowerBound ? target - rows.count : target)
        read(entries)
    }

    /// Puts the cues and headings back together from rows in reading order.
    mutating func read(_ rows: [OutlineRow]) {
        var cues: [Cue] = [], groups: [CueGroup] = [], waiting: [CueGroup] = []
        for row in rows {
            switch row {
            case .group(let group, _, _):
                waiting.append(group)
            case .cue(let cue, _):
                groups += waiting.map { var g = $0; g.before = cue.id; return g }
                waiting = []
                cues.append(cue)
            }
        }
        self.cues = cues
        self.groups = groups + waiting.map { var g = $0; g.before = nil; return g }
    }
}

// MARK: - show.json

/// In show.json a heading sits in the running list of cues, where it reads:
/// `{"kind": "group", "id": …, "name": "Act One", "level": 0}`.
struct GroupEntry: Codable {
    var kind = "group"
    var id: UUID
    var name: String
    var level: Int

    init(_ group: CueGroup) {
        id = group.id
        name = group.name
        level = group.level
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        level = max(0, try c.decodeIfPresent(Int.self, forKey: .level) ?? 0)
    }
}

/// One entry of show.json's running list: a cue, or a heading.
enum SheetEntry: Codable {
    case cue(Cue)
    case group(GroupEntry)

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .kind)
        self = kind == "group" ? .group(try GroupEntry(from: decoder)) : .cue(try Cue(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .cue(let cue): try cue.encode(to: encoder)
        case .group(let group): try group.encode(to: encoder)
        }
    }
}
