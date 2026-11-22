import BackdropStage
import SwiftUI

/// Beginners: before the first GO, in the On stage monitor's place, every
/// check the Booth can make, green when fine and in amber or red when not,
/// then what macOS can't check, as reminders.
struct BeginnersView: View {
    let checks: [BoothCheck]
    var onOpenProjector: () -> Void = {}

    private static let reminders = ["A Focus mode is on", "The projector\u{2019}s wallpaper is black", "Automatic updates are off"]

    var body: some View {
        ScrollView(.vertical) { content }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: Booth.panel))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEGINNERS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(2)
                .foregroundStyle(Color(nsColor: Booth.brass))
            // The projector first, across the whole width: it matters most,
            // and may carry a button.
            if let projector = checks.first(where: { $0.id == .projector }) { row(projector) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .topLeading),
                                GridItem(.flexible(), spacing: 14, alignment: .topLeading)],
                      alignment: .leading, spacing: 2) {
                ForEach(Array(checks.filter { $0.id != .projector }.enumerated()), id: \.offset) { _, check in row(check) }
            }
            Text("REMINDERS \u{00B7} MACOS CAN\u{2019}T CHECK THESE")
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(Color(nsColor: Booth.dim))
                .padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .topLeading),
                                GridItem(.flexible(), spacing: 14, alignment: .topLeading)],
                      alignment: .leading, spacing: 2) {
                ForEach(Self.reminders, id: \.self) { reminder in
                    HStack(spacing: 8) {
                        Circle().strokeBorder(Color(nsColor: Booth.dim), lineWidth: 1.2).frame(width: 9, height: 9)
                        Text(reminder).lineLimit(1)
                    }
                    .frame(height: 20)
                    .foregroundStyle(Color(nsColor: Booth.dim))
                }
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ check: BoothCheck) -> some View {
        let colour: NSColor = switch check.state {
        case .fine: Booth.ok
        case .caution: Booth.amber
        case .stop: Booth.tally
        }
        return HStack(spacing: 8) {
            Circle().fill(Color(nsColor: colour)).frame(width: 7, height: 7)
            Text(check.text)
                .foregroundStyle(Color(nsColor: check.state == .fine ? Booth.ink : colour))
                .lineLimit(1)
                .truncationMode(.tail)
            if check.id == .projector, check.state == .stop {
                Button("Open Projector", action: onOpenProjector)
                    .controlSize(.small)
                    .focusable(false)
            }
        }
        .frame(minHeight: 20)
        .help([check.text, check.detail].compactMap { $0 }.joined(separator: "\n\n"))
    }
}
