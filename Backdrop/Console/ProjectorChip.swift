import BackdropCore
import BackdropStage
import SwiftUI

/// The projector's lamp: what it is doing, in today's words, green when
/// live, amber when it has a warning or the picture is blacked out, grey when
/// closed. Clicked, it offers the Show menu's projector items.
struct ProjectorChip: View {
    let lamp: String
    let live: Bool
    let warn: Bool
    let blackout: Bool
    let isOpen: Bool
    let room: Room
    var displays: () -> (items: [DisplayMenu.Item], note: String?) = { ([], nil) }
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    var onChoose: (DisplayIdentity) -> Void = { _ in }
    /// The Studio's chip shows what the projector shows, small. The picture
    /// is the console's own live surface, placed over this slot.
    var showsPicture = false
    var onPictureFrame: (CGRect) -> Void = { _ in }

    static let picture = CGSize(width: 54, height: 30)

    var body: some View {
        Menu {
            if isOpen {
                Button("Close Projector", action: onClose)
            } else {
                Button("Open Projector", action: onOpen)
            }
            Menu("Choose Projector Display") {
                let (items, note) = displays()
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Button {
                        if let display = item.display { onChoose(display) }
                    } label: {
                        if item.chosen { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }
                    .disabled(item.display == nil)
                }
                if let note {
                    Divider()
                    Text(note)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if showsPicture {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.black)
                        .frame(width: Self.picture.width, height: Self.picture.height)
                }
                lampMark
                Text(lamp)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: live || warn ? lampColour : room.ink))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: room.panel)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: room.line)))
        }
        // Measured from outside the menu: its label is drawn apart from the
        // header, where the header's coordinates don't reach. The picture's
        // slot is at the chip's left, inside its padding.
        .background(GeometryReader { geometry in
            // In the window's coordinates, from its top left corner; the
            // console takes off its title bar.
            let chip = geometry.frame(in: .global)
            let slot = showsPicture
                ? CGRect(x: chip.minX + 12, y: chip.midY - Self.picture.height / 2,
                         width: Self.picture.width, height: Self.picture.height)
                : .zero
            Color.clear
                .onAppear { onPictureFrame(slot) }
                .onChange(of: slot) { _, new in onPictureFrame(new) }
        })
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .help("The projector. Click to open or close it, or choose its display")
    }

    /// Green only when live: nothing else in the Booth is green. Crossed out
    /// while blacked out.
    @ViewBuilder private var lampMark: some View {
        if blackout {
            Image(systemName: "circle.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: room.amber))
        } else {
            Circle().fill(Color(nsColor: lampColour)).frame(width: 8, height: 8)
        }
    }

    private var lampColour: NSColor {
        if blackout || warn { return room.amber }
        return live ? room.ok : room.dim
    }
}

/// Cautions, as amber lamps: one short label each. Clicking one shows its
/// whole message on the caution line.
struct CautionLamps: View {
    let cautions: [BoothWarning]
    let selected: BoothWarning.ID?
    let room: Room
    var onSelect: (BoothWarning.ID) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(cautions.enumerated()), id: \.offset) { _, caution in
                Button { onSelect(caution.id) } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: room.amber)).frame(width: 7, height: 7)
                        Text(caution.lamp ?? "")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(nsColor: room.amber))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(nsColor: room.amber).opacity(selected == caution.id ? 0.24 : 0.12)))
                    .overlay(Capsule().strokeBorder(Color(nsColor: room.amber).opacity(0.5)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(caution.message)
            }
        }
        .fixedSize()
    }
}
