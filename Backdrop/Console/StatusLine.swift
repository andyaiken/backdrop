import AppKit
import BackdropCore
import SwiftUI

/// What the console last said, at the foot of the rail. A message from
/// show control or a shortcut carries a badge saying where it came from,
/// flashes green as it arrives, and goes after eight seconds unless another
/// replaces it. Every other message stays until something clears it.
@MainActor
final class StatusLine: NSView {
    private let host = NSHostingView(rootView: StatusLineView(text: "", badge: nil, flash: false, room: .studio))
    private var hide: DispatchWorkItem?
    private var settle: DispatchWorkItem?
    private(set) var text = ""
    private var origin: CommandSource?
    private var room = Room.studio

    static let fadesAfter: TimeInterval = 8
    static let flashFor: TimeInterval = 0.6

    init() {
        super.init(frame: .zero)
        addSubview(host)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    /// The height it needs at a width, or nothing when it has nothing to say.
    func height(width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        host.frame.size.width = width
        return ceil(host.fittingSize.height)
    }

    func update(message: String?, origin: CommandSource?, room: Room) {
        let text = message ?? ""
        let roomChanged = self.room.background != room.background
        self.room = room
        guard text != self.text || origin != self.origin || roomChanged else { return }
        let fresh = text != self.text || origin != self.origin
        self.text = text
        self.origin = origin
        guard fresh else { return show(flash: false) }
        hide?.cancel()
        settle?.cancel()
        show(flash: origin != nil && !text.isEmpty)
        guard origin != nil, !text.isEmpty else { return }
        let settle = DispatchWorkItem { [weak self] in self?.show(flash: false) }
        let hide = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.text = ""
            self.show(flash: false)
            self.superview?.needsLayout = true
        }
        self.settle = settle
        self.hide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashFor, execute: settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadesAfter, execute: hide)
    }

    private func show(flash: Bool) {
        host.rootView = StatusLineView(text: text, badge: text.isEmpty ? nil : origin?.badge, flash: flash, room: room)
        isHidden = text.isEmpty
    }
}

struct StatusLineView: View {
    let text: String
    let badge: String?
    let flash: Bool
    let room: Room

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(Color(nsColor: room.ok))
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: room.ink))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: flash ? room.ok : room.panel).opacity(flash ? 0.25 : 1))
                .animation(.easeOut(duration: 0.3), value: flash)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: room.line)))
        .fixedSize(horizontal: false, vertical: true)
    }
}
