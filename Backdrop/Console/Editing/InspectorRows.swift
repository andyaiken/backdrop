import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a row being dragged up or down an Inspector list would land: before
/// the item at `gap`, or at the end when `gap` is the count. `row` is what
/// the pointer is over, so leaving one row doesn't clear what the next has
/// just set.
struct RowDropTarget: Equatable {
    let row: Int
    let gap: Int
}

/// Dragging the rows of an Inspector list, a layered cue's layers or a
/// morph's pictures, into a new order.
enum RowReorder {
    /// What a dragged row carries: its list and its place, so only a row of
    /// the same list can land.
    static func payload(_ list: String, _ index: Int) -> NSItemProvider {
        NSItemProvider(object: "\(prefix(list))\(index)" as NSString)
    }

    static func prefix(_ list: String) -> String { "backdrop-\(list):" }

    /// The place an item takes for a drop before `gap`: taken out first, so a
    /// later place is one fewer.
    static func destination(from: Int, gap: Int) -> Int {
        gap > from ? gap - 1 : gap
    }

    /// A brass bar where a dragged row will land.
    static var insertion: some View {
        Capsule().fill(Color(nsColor: Desk.brass)).frame(height: 3)
    }
}

extension View {
    /// Clears a landing place left showing by a drag that ended without
    /// leaving the row it was over. The pointer moving over the list with
    /// no button down means no drag is under way.
    func clearsStaleRowDrop(_ target: Binding<RowDropTarget?>) -> some View {
        onContinuousHover { _ in
            if target.wrappedValue != nil { target.wrappedValue = nil }
        }
    }
}

/// A row of a list being dragged over another row of the same list.
struct RowReorderDrop: DropDelegate {
    let list: String
    /// What the pointer is over: any number no other row of the list uses.
    let row: Int
    /// Where a drop would land, from how far down the row the pointer is.
    let gap: (CGFloat) -> Int
    @Binding var target: RowDropTarget?
    let move: @MainActor @Sendable (_ from: Int, _ to: Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        // Files go to the list's own drop, which adds them.
        info.hasItemsConforming(to: [.plainText]) && !info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) { aim(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        aim(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.row == row { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let gap = target?.gap ?? self.gap(info.location.y)
        target = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let prefix = RowReorder.prefix(list), move = self.move
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? String, text.hasPrefix(prefix), let from = Int(text.dropFirst(prefix.count)) else { return }
            Task { @MainActor in
                let to = RowReorder.destination(from: from, gap: gap)
                if to != from { move(from, to) }
            }
        }
        return true
    }

    private func aim(_ info: DropInfo) {
        target = RowDropTarget(row: row, gap: gap(info.location.y))
    }
}

/// The controls at the trailing end of an Inspector list row: its menu, a
/// trash can as the cue list deletes with, and a drag handle. They show only
/// while the pointer is over the row, over the end of its name, which fades
/// out beneath them rather than moving up to make room.
struct RowControls<Items: View>: View {
    let showing: Bool
    let menuHelp: String
    let removeHelp: String
    let dragHelp: String
    let remove: () -> Void
    @ViewBuilder let menu: () -> Items

    /// The room they take at the row's end, and the fade before it.
    static var width: CGFloat { 68 }
    static var fade: CGFloat { 24 }

    var body: some View {
        HStack(spacing: 8) {
            Menu { menu() } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(menuHelp)
            Button(action: remove) { Image(systemName: "trash").foregroundStyle(.secondary) }
                .buttonStyle(.borderless)
                .help(removeHelp)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(dragHelp)
        }
        .frame(width: Self.width, alignment: .trailing)
        // Kept, not removed, so a menu open from them keeps its button.
        .opacity(showing ? 1 : 0)
        .allowsHitTesting(showing)
    }
}

extension View {
    /// Fades this out at its trailing end, so a name too long for the row
    /// fades rather than being cut off, and while a row's controls show
    /// there, before them, so it gives way to them. A name that fits is
    /// untouched.
    func fadesUnderRowControls(_ showing: Bool) -> some View {
        mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: showing ? RowControls<EmptyView>.fade : 12)
                if showing {
                    Color.clear.frame(width: RowControls<EmptyView>.width)
                }
            }
        }
    }
}
